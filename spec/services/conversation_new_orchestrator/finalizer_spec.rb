# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationNewOrchestrator::Finalizer do
  let(:conversation) { instance_double(Conversation, id: 123, active?: true, end!: nil) }
  let(:session_id) { 'test_session_123' }
  let(:user_message) { 'Turn on the lights' }

  let(:state) do
    {
      session_id: session_id,
      conversation: conversation,
      ai_response: {
        id: 'response_123',
        text: 'I have turned on the lights.',
        speech_text: 'I have turned on the lights.',
        continue_conversation: false,
        inner_thoughts: 'User requested lighting control',
        current_mood: 'helpful',
        pressing_questions: nil,
        goal_progress: nil
      },
      action_results: {
        sync_results: {
          'lights.control' => { success: true, message: 'Light turned on' }
        },
        delegated_intents: []
      }
    }
  end

  describe '.call' do
    before do
      allow(ConversationLog).to receive(:create!)
      allow(ConversationLogger).to receive(:conversation_ended)
      allow(ConversationResponse).to receive(:action_done).and_return(
        double(to_home_assistant_response: { response_type: 'action_done' })
      )
    end

    context 'with successful completion' do
      it 'stores conversation log and returns formatted response' do
        result = described_class.call(state: state, user_message: user_message)

        expect(result.success?).to be true
        expect(ConversationLog).to have_received(:create!).with(
          session_id: session_id,
          user_message: user_message,
          ai_response: 'I have turned on the lights.',
          tool_results: '{"lights.control":{"success":true,"message":"Light turned on"}}',
          metadata: hash_including(:response_id, :inner_thoughts, :current_mood)
        )
      end

      it 'logs conversation ended event' do
        described_class.call(state: state, user_message: user_message)

        expect(ConversationLogger).to have_received(:conversation_ended).with(
          session_id,
          'I have turned on the lights.',
          false, # continue_conversation
          hash_including(:sync_tools, :async_tools)
        )
      end

      it 'formats response for Home Assistant' do
        result = described_class.call(state: state, user_message: user_message)

        expect(ConversationResponse).to have_received(:action_done).with(
          'I have turned on the lights.',
          hash_including(:success_entities, :targets, :continue_conversation, :conversation_id)
        )

        expect(result.data[:hass_response]).to include(:end_conversation)
      end
    end

    context 'with continue_conversation true' do
      before do
        state[:ai_response][:continue_conversation] = true
      end

      it 'does not end the conversation' do
        allow(conversation).to receive(:end!)

        described_class.call(state: state, user_message: user_message)

        expect(conversation).not_to have_received(:end!)
      end

      it 'sets continue_conversation and end_conversation correctly' do
        result = described_class.call(state: state, user_message: user_message)

        expect(ConversationResponse).to have_received(:action_done).with(
          anything,
          hash_including(continue_conversation: true)
        )
      end
    end

    context 'with async tools pending' do
      before do
        state[:action_results][:delegated_intents] = [
          { 'tool' => 'async.tool', 'parameters' => {} }
        ]
      end

      it 'keeps conversation active due to pending async tools' do
        allow(conversation).to receive(:end!)

        described_class.call(state: state, user_message: user_message)

        expect(conversation).not_to have_received(:end!)
      end

      it 'includes async tools in success entities' do
        described_class.call(state: state, user_message: user_message)

        expect(ConversationResponse).to have_received(:action_done).with(
          anything,
          hash_including(
            success_entities: array_including(
              hash_including(entity_id: 'async.tool', state: 'pending')
            )
          )
        )
      end
    end

    context 'when conversation should end' do
      before do
        state[:ai_response][:continue_conversation] = false
        allow(conversation).to receive(:end!)
      end

      it 'ends the conversation' do
        described_class.call(state: state, user_message: user_message)

        expect(conversation).to have_received(:end!)
      end
    end

    context 'when conversation is already inactive' do
      before do
        allow(conversation).to receive(:active?).and_return(false)
        allow(conversation).to receive(:end!)
      end

      it 'does not try to end inactive conversation' do
        described_class.call(state: state, user_message: user_message)

        expect(conversation).not_to have_received(:end!)
      end
    end

    context 'with memory search tools' do
      before do
        state[:action_results][:sync_results]['memory_search.rag'] = {
          success: true,
          results: [ 'Found 2 entries' ]
        }
      end

      it 'categorizes memory search as query tool' do
        described_class.call(state: state, user_message: user_message)

        # Verify that metadata includes the correct tool categorization
        expect(ConversationLog).to have_received(:create!).with(
          hash_including(
            metadata: hash_including(
              sync_tools: array_including('lights.control', 'memory_search.rag')
            )
          )
        )
      end
    end

    context 'when an error occurs during finalization' do
      before do
        allow(ConversationLog).to receive(:create!).and_raise(StandardError.new("Database error"))
      end

      it 'returns a failure result' do
        result = described_class.call(state: state, user_message: user_message)

        expect(result.success?).to be false
        expect(result.error).to include("Finalization failed")
      end
    end

    context 'with missing ai_response data' do
      before do
        state[:ai_response] = { text: 'Simple response' }
      end

      it 'handles missing narrative fields gracefully' do
        result = described_class.call(state: state, user_message: user_message)

        expect(result.success?).to be true
        expect(ConversationLog).to have_received(:create!).with(
          hash_including(
            metadata: hash_including(
              inner_thoughts: nil,
              current_mood: nil,
              pressing_questions: nil,
              continue_conversation_from_llm: nil,
              goal_progress: nil
            )
          )
        )
      end
    end
  end
end
