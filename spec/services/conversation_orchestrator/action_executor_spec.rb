# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationOrchestrator::ActionExecutor do
  let(:session_id) { 'test_session_123' }
  let(:conversation_id) { 456 }
  let(:user_message) { 'Turn on the lights' }

  describe '.call' do
    context 'with actions for delegation' do
      let(:llm_response) do
        { "actions" => [
          { "action_name" => "cube_light", "description" => "turn the kitchen lights orange" },
          { "action_name" => "sound", "description" => "play heavy metal" }
        ] }
      end

      it 'flattens the actions and dispatches them to EnvironmentDirectorJob' do
        expect(EnvironmentDirectorJob).to receive(:perform_later).with(
          hash_including(
            instruction: "cube_light: turn the kitchen lights orange; sound: play heavy metal",
            session_id: session_id,
            conversation_id: conversation_id,
            user_message: user_message
          )
        )

        result = described_class.call(
          llm_response: llm_response,
          session_id: session_id,
          conversation_id: conversation_id,
          user_message: user_message
        )

        expect(result.success?).to be true
        expect(result.data[:dispatched_environment]).to be true
      end
    end

    context 'with an empty actions array' do
      let(:llm_response) { { "actions" => [] } }

      it 'does not dispatch and returns dispatched_environment: false' do
        expect(EnvironmentDirectorJob).not_to receive(:perform_later)

        result = described_class.call(
          llm_response: llm_response,
          session_id: session_id,
          conversation_id: conversation_id,
          user_message: user_message
        )

        expect(result.success?).to be true
        expect(result.data[:dispatched_environment]).to be false
      end
    end

    context 'with empty LLM response' do
      let(:llm_response) { {} }

      it 'returns success with empty results' do
        result = described_class.call(
          llm_response: llm_response,
          session_id: session_id,
          conversation_id: conversation_id,
          user_message: user_message
        )

        expect(result.success?).to be true
        expect(result.data[:sync_results]).to eq({})
        expect(result.data[:dispatched_environment]).to be false
      end
    end
  end
end
