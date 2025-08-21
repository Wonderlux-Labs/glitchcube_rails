# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Direct Tool Calling Integration", type: :integration do
  let(:conversation_orchestrator) do
    ConversationOrchestrator.new(
      session_id: "test_session",
      message: "Search for fire spinning events",
      context: { source: "test" }
    )
  end

  let(:structured_response) do
    OpenStruct.new(
      structured_output: {
        "speech_text" => "I found some fire spinning events for you!",
        "continue_conversation" => true,
        "direct_tool_calls" => [
          {
            "tool_name" => "rag_search",
            "parameters" => {
              "query" => "fire spinning",
              "type" => "events",
              "limit" => 3
            }
          }
        ],
        "tool_intents" => [
          {
            "tool" => "lights",
            "intent" => "Make lights warm and orange like fire"
          }
        ]
      }
    )
  end

  before do
    # Mock the LLM service to return our structured response
    allow(LlmService).to receive(:call_with_structured_output).and_return(structured_response)
    
    # Mock the HA agent delegation
    allow(conversation_orchestrator).to receive(:delegate_to_ha_agent)
    
    # Mock the final response generation
    allow(conversation_orchestrator).to receive(:generate_ai_response).and_return("Mocked AI response")
    allow(conversation_orchestrator).to receive(:store_conversation_log)
    allow(conversation_orchestrator).to receive(:format_response_for_hass).and_return({ speech: "Test response" })
  end

  describe "#execute_direct_tools" do
    it "executes direct tools and returns results" do
      direct_tool_calls = [
        {
          "tool_name" => "rag_search",
          "parameters" => {
            "query" => "fire spinning",
            "type" => "events",
            "limit" => 3
          }
        }
      ]

      results = conversation_orchestrator.send(:execute_direct_tools, direct_tool_calls)
      
      expect(results).to have_key("rag_search")
      expect(results["rag_search"]).to have_key(:success)
    end

    it "handles tool execution errors gracefully" do
      direct_tool_calls = [
        {
          "tool_name" => "nonexistent_tool",
          "parameters" => {}
        }
      ]

      results = conversation_orchestrator.send(:execute_direct_tools, direct_tool_calls)
      
      expect(results).to have_key("nonexistent_tool")
      expect(results["nonexistent_tool"][:success]).to be false
      expect(results["nonexistent_tool"][:error]).to be_present
    end
  end

  describe "#execute_memory_searches" do
    let(:memory_searches) do
      [
        {
          "query" => "fire spinning",
          "type" => "events",
          "limit" => 3
        },
        {
          "query" => "music discussion",
          "type" => "summaries"
        }
      ]
    end

    it "executes multiple memory searches" do
      results = conversation_orchestrator.send(:execute_memory_searches, memory_searches)
      
      expect(results).to have_key("memory_search_1")
      expect(results).to have_key("memory_search_2")
    end

    it "uses RAG search tool for memory searches" do
      expect(Tools::Registry).to receive(:execute_tool).with(
        "rag_search",
        query: "fire spinning",
        type: "events",
        limit: 3
      ).and_return({ success: true, results: [] })

      expect(Tools::Registry).to receive(:execute_tool).with(
        "rag_search",
        query: "music discussion",
        type: "summaries",
        limit: 3
      ).and_return({ success: true, results: [] })

      conversation_orchestrator.send(:execute_memory_searches, memory_searches)
    end

    it "handles memory search errors gracefully" do
      allow(Tools::Registry).to receive(:execute_tool).and_raise(StandardError.new("Search failed"))
      
      results = conversation_orchestrator.send(:execute_memory_searches, memory_searches)
      
      expect(results["memory_search_1"][:success]).to be false
      expect(results["memory_search_1"][:error]).to eq("Search failed")
    end
  end

  describe "full dual tool execution flow" do
    let!(:event) { create(:event, title: "Fire Show", description: "Amazing fire spinning") }
    
    before do
      # Mock the similarity search to return our event
      allow(Event).to receive(:similarity_search).and_return([event])
      allow(Summary).to receive(:similarity_search).and_return([])
      allow(Person).to receive(:similarity_search).and_return([])
    end

    it "executes both direct tools and delegates to HA agent" do
      expect(conversation_orchestrator).to receive(:delegate_to_ha_agent).with([
        {
          "tool" => "lights",
          "intent" => "Make lights warm and orange like fire"
        }
      ])

      # Execute the full flow
      conversation_orchestrator.call

      # Verify logging messages
      expect(Rails.logger).to have_received(:info).with(/🔧 Executed .* direct tools/)
      expect(Rails.logger).to have_received(:info).with(/🏠 Found .* tool intentions/)
    end

    it "combines all tool results for final response generation" do
      expect(conversation_orchestrator).to receive(:generate_ai_response) do |prompt_data, response, all_results|
        # Verify that all_results includes direct tool results
        expect(all_results).to have_key("rag_search")
        "Generated response with tool results"
      end

      conversation_orchestrator.call
    end

    it "properly categorizes tools in analysis" do
      allow(conversation_orchestrator).to receive(:store_conversation_log) do |conversation, ai_response, results, tool_analysis|
        expect(tool_analysis[:sync_tools]).to include("rag_search")
        expect(tool_analysis[:async_tools]).to include("lights")
        expect(tool_analysis[:query_tools]).to include("rag_search")
        expect(tool_analysis[:action_tools]).to be_empty  # rag_search is not an action tool
      end

      conversation_orchestrator.call
    end
  end

  describe "error handling in dual tool system" do
    let(:failing_structured_response) do
      OpenStruct.new(
        structured_output: {
          "speech_text" => "Let me help you!",
          "continue_conversation" => true,
          "direct_tool_calls" => [
            {
              "tool_name" => "rag_search",
              "parameters" => { "query" => "" }  # Invalid empty query
            }
          ]
        }
      )
    end

    before do
      allow(LlmService).to receive(:call_with_structured_output).and_return(failing_structured_response)
    end

    it "handles direct tool failures without crashing" do
      expect { conversation_orchestrator.call }.not_to raise_error
    end

    it "logs direct tool failures appropriately" do
      conversation_orchestrator.call
      
      expect(Rails.logger).to have_received(:error).with(/❌ Direct tool execution failed/)
    end
  end
end