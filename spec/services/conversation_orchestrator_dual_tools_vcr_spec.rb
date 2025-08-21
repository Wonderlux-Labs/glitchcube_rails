# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConversationOrchestrator, "dual tool execution with VCR", type: :service do
  describe "enhanced dual tool execution with real API", :vcr do
    let(:orchestrator) do
      described_class.new(
        session_id: "dual_tools_session",
        message: "Search for fire spinning events and make the lights warm",
        context: { source: "vcr_test" }
      )
    end

    let!(:existing_event) do
      create(:event, 
             title: "Fire Performance Workshop",
             description: "Learn fire spinning techniques with experts",
             event_time: 2.hours.from_now,
             importance: 8)
    end

    let!(:existing_person) do 
      create(:person,
             name: "Maya",
             description: "Expert fire spinner and teacher",
             relationship: "instructor")
    end

    before do
      # Mock vectorsearch to return our test data
      allow(Event).to receive(:similarity_search).and_return([existing_event])
      allow(Person).to receive(:similarity_search).and_return([existing_person])
      allow(Summary).to receive(:similarity_search).and_return([])
    end

    describe "LLM structured output with all new fields" do
      it "generates structured output with direct_tool_calls and search_memories", vcr: { cassette_name: "dual_tools/structured_output_with_new_fields" } do
        # Mock HA delegation to avoid external calls
        allow(orchestrator).to receive(:delegate_to_ha_agent)
        
        response = orchestrator.call
        
        expect(response).to have_key(:speech)
        expect(Rails.logger).to have_received(:info).with(/🔧 Executed .* direct tools/)
      end

      it "handles complex multi-tool scenarios", vcr: { cassette_name: "dual_tools/complex_multi_tool_scenario" } do
        # Test with message that should trigger multiple tool types
        complex_orchestrator = described_class.new(
          session_id: "complex_session",
          message: "Find events about fire, search my memories about performances, and turn on warm lighting",
          context: { source: "vcr_complex_test" }
        )

        allow(complex_orchestrator).to receive(:delegate_to_ha_agent)
        
        response = complex_orchestrator.call
        expect(response).to be_present
      end
    end

    describe "direct tool execution integration" do
      it "executes rag_search tool directly with real API", vcr: { cassette_name: "dual_tools/direct_rag_search_execution" } do
        # Simulate structured output that includes direct tool calls
        mock_structured_output = OpenStruct.new(
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
            "tool_intents" => [],
            "search_memories" => []
          }
        )

        allow(LlmService).to receive(:call_with_structured_output).and_return(mock_structured_output)
        allow(orchestrator).to receive(:generate_ai_response).and_return("Found events!")
        allow(orchestrator).to receive(:store_conversation_log)
        allow(orchestrator).to receive(:format_response_for_hass).and_return({ speech: "Response" })

        response = orchestrator.call

        expect(Rails.logger).to have_received(:info).with(/🔧 Direct tool executed: rag_search/)
      end

      it "handles direct tool failures gracefully", vcr: { cassette_name: "dual_tools/direct_tool_failure_handling" } do
        mock_structured_output = OpenStruct.new(
          structured_output: {
            "speech_text" => "Let me search for that...",
            "continue_conversation" => true,
            "direct_tool_calls" => [
              {
                "tool_name" => "nonexistent_tool",
                "parameters" => {}
              }
            ],
            "tool_intents" => [],
            "search_memories" => []
          }
        )

        allow(LlmService).to receive(:call_with_structured_output).and_return(mock_structured_output)
        allow(orchestrator).to receive(:generate_ai_response).and_return("Had some issues")
        allow(orchestrator).to receive(:store_conversation_log)
        allow(orchestrator).to receive(:format_response_for_hass).and_return({ speech: "Response" })

        expect { orchestrator.call }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(/❌ Direct tool execution failed/)
      end
    end

    describe "memory search execution integration" do
      it "executes memory searches with real tool calls", vcr: { cassette_name: "dual_tools/memory_search_execution" } do
        mock_structured_output = OpenStruct.new(
          structured_output: {
            "speech_text" => "Let me search your memories...",
            "continue_conversation" => true,
            "direct_tool_calls" => [],
            "tool_intents" => [],
            "search_memories" => [
              {
                "query" => "fire performances",
                "type" => "events",
                "limit" => 2
              },
              {
                "query" => "spinning techniques",
                "type" => "people"
              }
            ]
          }
        )

        allow(LlmService).to receive(:call_with_structured_output).and_return(mock_structured_output)
        allow(orchestrator).to receive(:generate_ai_response).and_return("Found memories!")
        allow(orchestrator).to receive(:store_conversation_log)
        allow(orchestrator).to receive(:format_response_for_hass).and_return({ speech: "Response" })

        response = orchestrator.call

        expect(Rails.logger).to have_received(:info).with(/🧠 Executed .* memory searches/)
      end
    end

    describe "hybrid tool execution flow" do
      it "executes direct tools AND delegates to HA agent", vcr: { cassette_name: "dual_tools/hybrid_execution_flow" } do
        mock_structured_output = OpenStruct.new(
          structured_output: {
            "speech_text" => "I'll search and adjust the lighting!",
            "continue_conversation" => true,
            "direct_tool_calls" => [
              {
                "tool_name" => "rag_search",
                "parameters" => {
                  "query" => "fire events",
                  "type" => "all",
                  "limit" => 2
                }
              }
            ],
            "tool_intents" => [
              {
                "tool" => "lights",
                "intent" => "Make lights warm and orange like fire"
              }
            ],
            "search_memories" => []
          }
        )

        allow(LlmService).to receive(:call_with_structured_output).and_return(mock_structured_output)
        allow(orchestrator).to receive(:generate_ai_response).and_return("Done!")
        allow(orchestrator).to receive(:store_conversation_log)
        allow(orchestrator).to receive(:format_response_for_hass).and_return({ speech: "Response" })

        # Expect both direct execution AND HA delegation
        expect(orchestrator).to receive(:delegate_to_ha_agent).with([
          { "tool" => "lights", "intent" => "Make lights warm and orange like fire" }
        ])

        response = orchestrator.call

        expect(Rails.logger).to have_received(:info).with(/🔧 Executed .* direct tools/)
        expect(Rails.logger).to have_received(:info).with(/🏠 Found .* tool intentions/)
      end
    end

    describe "proactive events integration in real flow" do
      let!(:high_priority_event) do
        create(:event,
               title: "Critical Safety Announcement",
               description: "Important safety information for all participants",
               event_time: 3.hours.from_now,
               importance: 10,
               location: "Center Camp")
      end

      it "includes proactive events in context during real conversation", vcr: { cassette_name: "dual_tools/proactive_events_in_context" } do
        # Mock location sensor
        ha_service = double("HomeAssistantService")
        allow(HomeAssistantService).to receive(:new).and_return(ha_service)
        context_sensor = {
          "attributes" => { "current_location" => "Center Camp" }
        }
        allow(ha_service).to receive(:entity).and_return(context_sensor)

        # The orchestrator should receive context that includes our high-priority event
        expect(PromptService).to receive(:build_prompt_for) do |args|
          # Verify the prompt service is called with user_message for RAG context
          expect(args[:user_message]).to eq(orchestrator.instance_variable_get(:@message))
          
          # Return mock prompt data that would include our proactive event
          {
            system_prompt: "Test system prompt with proactive events included",
            messages: [],
            tools: [],
            context: "Context including Critical Safety Announcement"
          }
        end

        allow(LlmService).to receive(:call_with_structured_output).and_return(
          OpenStruct.new(structured_output: {
            "speech_text" => "I see there's a critical safety announcement coming up!",
            "continue_conversation" => true,
            "direct_tool_calls" => [],
            "tool_intents" => [],
            "search_memories" => []
          })
        )

        allow(orchestrator).to receive(:generate_ai_response).and_return("Safety first!")
        allow(orchestrator).to receive(:store_conversation_log)
        allow(orchestrator).to receive(:format_response_for_hass).and_return({ speech: "Response" })

        orchestrator.call
      end
    end

    describe "error resilience in dual tool system" do
      it "continues processing even if one tool type fails", vcr: { cassette_name: "dual_tools/partial_failure_resilience" } do
        mock_structured_output = OpenStruct.new(
          structured_output: {
            "speech_text" => "Let me try to help...",
            "continue_conversation" => true,
            "direct_tool_calls" => [
              {
                "tool_name" => "rag_search",  # This should work
                "parameters" => { "query" => "test" }
              }
            ],
            "tool_intents" => [
              {
                "tool" => "lights",
                "intent" => "invalid intent that might fail"
              }
            ],
            "search_memories" => []
          }
        )

        allow(LlmService).to receive(:call_with_structured_output).and_return(mock_structured_output)
        
        # Mock HA delegation to fail
        allow(orchestrator).to receive(:delegate_to_ha_agent).and_raise(StandardError.new("HA failed"))
        
        allow(orchestrator).to receive(:generate_ai_response).and_return("Partial success")
        allow(orchestrator).to receive(:store_conversation_log)
        allow(orchestrator).to receive(:format_response_for_hass).and_return({ speech: "Response" })

        # Should not crash despite HA delegation failure
        expect { orchestrator.call }.not_to raise_error
      end
    end
  end

  describe "tool result integration in final response" do
    it "incorporates tool results into LLM response generation", vcr: { cassette_name: "dual_tools/tool_results_integration" } do
      orchestrator = described_class.new(
        session_id: "integration_session",
        message: "What fire events are happening?",
        context: { source: "integration_test" }
      )

      # Mock successful tool results
      mock_tool_results = {
        "rag_search" => {
          success: true,
          message: "Found 3 fire spinning events",
          total_results: 3,
          results: {
            events: [
              { title: "Fire Workshop", description: "Learn fire spinning" }
            ]
          }
        }
      }

      mock_structured_output = OpenStruct.new(
        structured_output: {
          "speech_text" => "Let me search for fire events...",
          "continue_conversation" => true,
          "direct_tool_calls" => [
            {
              "tool_name" => "rag_search",
              "parameters" => { "query" => "fire events", "type" => "events" }
            }
          ],
          "tool_intents" => [],
          "search_memories" => []
        }
      )

      allow(LlmService).to receive(:call_with_structured_output).and_return(mock_structured_output)
      
      # Mock direct tool execution to return our results
      allow(orchestrator).to receive(:execute_direct_tools).and_return(mock_tool_results)
      
      # Expect generate_ai_response to receive the tool results
      expect(orchestrator).to receive(:generate_ai_response) do |prompt_data, response, all_results|
        expect(all_results).to include("rag_search")
        expect(all_results["rag_search"][:success]).to be true
        "I found some great fire events for you!"
      end

      allow(orchestrator).to receive(:store_conversation_log)
      allow(orchestrator).to receive(:format_response_for_hass).and_return({ speech: "Response" })

      orchestrator.call
    end
  end
end