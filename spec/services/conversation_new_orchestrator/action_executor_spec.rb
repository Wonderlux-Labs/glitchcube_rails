# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationNewOrchestrator::ActionExecutor do
  let(:session_id) { 'test_session_123' }
  let(:conversation_id) { 456 }
  let(:user_message) { 'Turn on the lights' }

  describe '.call' do
    context 'with direct tool calls' do
      let(:llm_response) do
        {
          "direct_tool_calls" => [
            {
              "tool_name" => "lights.control",
              "parameters" => { "action" => "turn_on", "entity_id" => "light.living_room" }
            }
          ]
        }
      end

      before do
        allow(Tools::Registry).to receive(:execute_tool)
          .with("lights.control", action: "turn_on", entity_id: "light.living_room")
          .and_return({ success: true, message: "Light turned on" })
      end

      it 'executes direct tools and returns results' do
        result = described_class.call(
          llm_response: llm_response,
          session_id: session_id,
          conversation_id: conversation_id,
          user_message: user_message
        )

        expect(result.success?).to be true
        expect(result.data[:sync_results]).to include("lights.control" => { success: true, message: "Light turned on" })
      end
    end

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

    context 'with tool intents for delegation' do
      let(:llm_response) do
        {
          "tool_intents" => [
            {
              "tool" => "home_assistant.call_service",
              "intent" => "turn_on_lights",
              "parameters" => { "entity_id" => "light.kitchen" }
            }
          ]
        }
      end

      it 'delegates tool intents and marks them for async execution' do
        result = described_class.call(
          llm_response: llm_response,
          session_id: session_id,
          conversation_id: conversation_id,
          user_message: user_message
        )

        expect(result.success?).to be true
        expect(result.data[:delegated_intents]).to eq(llm_response["tool_intents"])
      end
    end

    context 'when tool execution fails' do
      let(:llm_response) do
        {
          "direct_tool_calls" => [
            {
              "tool_name" => "broken.tool",
              "parameters" => {}
            }
          ]
        }
      end

      before do
        allow(Tools::Registry).to receive(:execute_tool)
          .with("broken.tool")
          .and_raise(StandardError.new("Tool is broken"))
      end

      it 'captures tool failures gracefully' do
        result = described_class.call(
          llm_response: llm_response,
          session_id: session_id,
          conversation_id: conversation_id,
          user_message: user_message
        )

        expect(result.success?).to be true
        expect(result.data[:sync_results]["broken.tool"]).to include(
          success: false,
          error: "Tool is broken"
        )
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
        expect(result.data[:delegated_intents]).to eq([])
      end
    end
  end
end
