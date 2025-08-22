require 'rails_helper'

RSpec.describe ConversationNewOrchestrator::Setup do
  let(:session_id) { 'test-session-123' }
  let(:context) { { user_input: 'Hello', timestamp: Time.current } }
  let(:current_persona) { :buddy }

  before do
    # Ensure we have a current persona for testing
    allow(CubePersona).to receive(:current_persona).and_return(current_persona)
  end

  describe '#call' do
    subject(:result) { described_class.new(session_id: session_id, context: context).call }

    context 'with a new session' do
      it 'returns success with conversation, persona, and session_id' do
        expect(result).to be_success
        expect(result.data).to have_key(:conversation)
        expect(result.data).to have_key(:persona)
        expect(result.data).to have_key(:session_id)
        expect(result.data[:session_id]).to eq(session_id)
        expect(result.data[:persona]).to eq(current_persona)
      end

      it 'creates a new conversation with the session_id' do
        expect { result }.to change(Conversation, :count).by(1)

        conversation = result.data[:conversation]
        expect(conversation.session_id).to eq(session_id)
        expect(conversation).to be_persisted
      end
    end

    context 'with an existing fresh session' do
      let!(:existing_conversation) do
        create(:conversation, session_id: session_id, created_at: 2.minutes.ago)
      end

      it 'returns the existing conversation without creating a new one' do
        expect { result }.not_to change(Conversation, :count)

        expect(result).to be_success
        expect(result.data[:conversation]).to eq(existing_conversation)
        expect(result.data[:session_id]).to eq(session_id)
      end
    end

    context 'with a stale session (older than 5 minutes)' do
      let!(:stale_conversation) do
        conversation = create(:conversation, session_id: session_id, created_at: 6.minutes.ago)
        # Add conversation log to make it actually stale according to business logic
        conversation.conversation_logs.create!(
          user_message: "old message",
          ai_response: "old response",
          created_at: 6.minutes.ago
        )
        conversation
      end

      it 'generates a new session_id with "_stale_" suffix' do
        expect(result).to be_success

        new_session_id = result.data[:session_id]
        expect(new_session_id).to include('_stale_')
        expect(new_session_id).to start_with(session_id)
      end

      it 'creates a new conversation with the stale session_id' do
        expect { result }.to change(Conversation, :count).by(1)

        conversation = result.data[:conversation]
        expect(conversation.session_id).to include('_stale_')
        expect(conversation.session_id).to start_with(session_id)
        expect(conversation).not_to eq(stale_conversation)
      end

      it 'ends the original stale conversation' do
        expect(stale_conversation).to be_active

        result

        stale_conversation.reload
        expect(stale_conversation).not_to be_active
        expect(stale_conversation.session_id).to eq(session_id)
      end
    end

    context 'when no current persona exists' do
      before do
        allow(CubePersona).to receive(:current_persona).and_return(nil)
      end

      it 'returns failure with appropriate error message' do
        expect(result).to be_failure
        expect(result.error).to include('No current persona found')
      end

      it 'does not create a conversation' do
        expect { result }.not_to change(Conversation, :count)
      end
    end

    context 'parameter validation' do
      context 'when session_id is missing' do
        let(:session_id) { nil }

        it 'returns failure with validation error' do
          expect(result).to be_failure
          expect(result.error).to include('session_id is required')
        end
      end

      context 'when session_id is empty string' do
        let(:session_id) { '' }

        it 'returns failure with validation error' do
          expect(result).to be_failure
          expect(result.error).to include('session_id is required')
        end
      end

      context 'when context is missing' do
        let(:context) { nil }

        it 'returns failure with validation error' do
          expect(result).to be_failure
          expect(result.error).to include('context is required')
        end
      end
    end
  end

  describe 'stale session detection logic' do
    let(:fresh_time) { 3.minutes.ago }
    let(:stale_time) { 6.minutes.ago }

    context 'boundary condition at exactly 5 minutes' do
      let!(:boundary_conversation) do
        conversation = create(:conversation, session_id: session_id, created_at: 5.minutes.ago)
        conversation.conversation_logs.create!(
          user_message: "boundary message",
          ai_response: "boundary response",
          created_at: 5.minutes.ago
        )
        conversation
      end

      it 'treats 5-minute-old conversations as stale' do
        result = described_class.call(session_id: session_id, context: context)
        expect(result).to be_success
        expect(result.data[:session_id]).to include('_stale_')
      end
    end
  end

  describe 'return data structure' do
    it 'returns ServiceResult with expected data keys' do
      result = described_class.call(session_id: session_id, context: context)
      expect(result).to be_success

      data = result.data
      expect(data).to be_a(Hash)
      expect(data.keys).to contain_exactly(:conversation, :persona, :session_id)

      expect(data[:conversation]).to be_a(Conversation)
      expect(data[:persona]).to be_a(Symbol)
      expect(data[:session_id]).to be_a(String)
    end
  end
end
