# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationNewOrchestrator::ActionExecutor do
  let(:session_id) { 'test_session_123' }
  let(:conversation_id) { 456 }
  let(:user_message) { 'Turn on the lights' }

  describe '.call' do
    context 'with memory searches' do
      let(:llm_response) do
        {
          "search_memories" => [
            {
              "query" => "previous light settings",
              "tool_name" => "rag_search"
            }
          ]
        }
      end

      before do
        allow(Tools::Registry).to receive(:execute_tool)
          .with("rag_search", query: "previous light settings", type: "all", limit: 3)
          .and_return({ success: true, results: [ "Found 2 entries" ] })
      end

      it 'executes memory searches and returns results' do
        result = described_class.call(
          llm_response: llm_response,
          session_id: session_id,
          conversation_id: conversation_id,
          user_message: user_message
        )

        expect(result.success?).to be true
        expect(result.data[:sync_results]).to include("memory_search_1" => { success: true, results: [ "Found 2 entries" ] })
      end
    end

    context 'with an environment instruction for delegation' do
      let(:llm_response) do
        { "environment_instruction" => "turn the kitchen lights orange" }
      end

      it 'dispatches the instruction to EnvironmentDirectorJob and signals dispatched_environment' do
        expect(EnvironmentDirectorJob).to receive(:perform_later).with(
          hash_including(
            instruction: "turn the kitchen lights orange",
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

    context 'with a blank environment instruction' do
      let(:llm_response) { { "environment_instruction" => "" } }

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
