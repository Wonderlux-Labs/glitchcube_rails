# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationOrchestrator::Finalizer do
  # Finalizer now persists metadata as a JSON string (metadata.to_json) rather
  # than a Hash, so assert against the parsed JSON instead of the raw value.
  def metadata_json_including(expected)
    satisfy("metadata JSON including #{expected.inspect}") do |value|
      parsed = JSON.parse(value)
      expected.all? do |key, matcher|
        next false unless parsed.key?(key.to_s)

        actual = parsed[key.to_s]
        # RSpec argument/value matchers (array_including, instance_of, ...) all
        # support the case-equality operator; plain expected values use ==.
        rspec_matcher = matcher.respond_to?(:matches?) || matcher.respond_to?(:description)
        rspec_matcher ? (matcher === actual) : (actual == matcher)
      end
    end
  end

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
        pressing_questions: nil
      },
      action_results: {
        sync_results: {
          'lights.control' => { success: true, message: 'Light turned on' }
        },
        dispatched_environment: false
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
          metadata: metadata_json_including(
            response_id: 'response_123',
            inner_thoughts: 'User requested lighting control',
            current_mood: 'helpful'
          )
        )
      end

      it 'logs conversation ended event' do
        described_class.call(state: state, user_message: user_message)

        expect(ConversationLogger).to have_received(:conversation_ended).with(
          session_id,
          'I have turned on the lights.',
          false, # continue_conversation
          hash_including(:sync_tools, :environment_dispatched),
          hash_including(inner_thoughts: 'User requested lighting control')
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

    context 'with environment instruction dispatched' do
      before do
        state[:action_results][:dispatched_environment] = true
      end

      it 'keeps conversation active while environment job runs' do
        allow(conversation).to receive(:end!)

        described_class.call(state: state, user_message: user_message)

        expect(conversation).not_to have_received(:end!)
      end

      it 'sets continue_conversation true in the HASS response' do
        described_class.call(state: state, user_message: user_message)

        expect(ConversationResponse).to have_received(:action_done).with(
          anything,
          hash_including(continue_conversation: true)
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
            metadata: metadata_json_including(
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

      it 'still returns success — Finalizer rescues create! errors internally' do
        result = described_class.call(state: state, user_message: user_message)

        expect(result.success?).to be true
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
            metadata: metadata_json_including(
              inner_thoughts: nil,
              current_mood: nil,
              pressing_questions: nil,
              continue_conversation_from_llm: nil
            )
          )
        )
      end
    end
  end
end
