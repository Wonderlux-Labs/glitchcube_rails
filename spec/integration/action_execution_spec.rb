# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Action Execution Integration", type: :integration do
  # Test the new ConversationNewOrchestrator action execution functionality
  # This replaces the deleted direct_tool_calling_spec.rb with new architecture

  let(:session_id) { "test_action_execution_123" }
  let(:context) do
    {
      conversation_id: session_id,
      device_id: "test_device_id",
      language: "en",
      voice_interaction: true,
      timestamp: Time.current.iso8601,
      ha_context: { agent_id: "test_agent" },
      source: "hass_conversation"
    }
  end

  before do
    # Mock external dependencies
    allow(HomeAssistantService).to receive(:entity).with("input_select.current_persona")
      .and_return({ "state" => "buddy" })
    allow(HomeAssistantService).to receive(:entity).with("input_select.cube_mode")
      .and_return({ "state" => "conversation" })

    # Clean up any existing conversations
    Conversation.where(session_id: session_id).destroy_all
  end

  describe "ActionExecutor" do
    let(:orchestrator) { ConversationNewOrchestrator.new(session_id: session_id, message: "test message", context: context) }

    it "executes sync tools directly" do
      # Test the ActionExecutor directly with sync tools
      llm_response = {
        "direct_tool_calls" => [
          {
            "tool_name" => "rag_search",
            "parameters" => {
              "query" => "fire spinning",
              "type" => "events",
              "limit" => 3
            }
          }
        ]
      }

      result = ConversationNewOrchestrator::ActionExecutor.call(
        llm_response: llm_response,
        session_id: session_id,
        conversation_id: session_id,
        user_message: "test message"
      )

      expect(result.success?).to be true
      expect(result.data[:sync_results]).to have_key("rag_search")
      expect(result.data[:sync_results]["rag_search"]).to have_key(:success)
    end

    it "handles tool execution errors gracefully" do
      # Test error handling in ActionExecutor
      llm_response = {
        "direct_tool_calls" => [
          {
            "tool_name" => "nonexistent_tool",
            "parameters" => {}
          }
        ]
      }

      result = ConversationNewOrchestrator::ActionExecutor.call(
        llm_response: llm_response,
        session_id: session_id,
        conversation_id: session_id,
        user_message: "test message"
      )

      expect(result.success?).to be true  # ActionExecutor handles errors gracefully
      expect(result.data[:sync_results]).to have_key("nonexistent_tool")

      nonexistent_result = result.data[:sync_results]["nonexistent_tool"]
      expect(nonexistent_result[:error]).to be_present
      expect(nonexistent_result[:error]).to eq("Tool 'nonexistent_tool' not found")
    end

    it "delegates async tools to Home Assistant" do
      # Mock the job that ActionExecutor tries to enqueue
      ha_agent_job_class = Class.new do
        def self.perform_later(*args)
          # Mock implementation - just return success
          true
        end
      end
      stub_const("HaAgentJob", ha_agent_job_class)

      # Test delegation of async tools
      llm_response = {
        "tool_intents" => [
          {
            "tool" => "light.living_room",
            "intent" => "Make lights warm and orange like fire"
          }
        ]
      }

      result = ConversationNewOrchestrator::ActionExecutor.call(
        llm_response: llm_response,
        session_id: session_id,
        conversation_id: session_id,
        user_message: "test message"
      )

      unless result.success?
        puts "ActionExecutor failed: #{result.error}"
      end
      expect(result.success?).to be true
      expect(result.data[:delegated_intents]).to include(
        hash_including("tool" => "light.living_room")
      )
    end

    it "handles mixed sync and async tools" do
      # Mock the job that ActionExecutor tries to enqueue
      ha_agent_job_class = Class.new do
        def self.perform_later(*args)
          true
        end
      end
      stub_const("HaAgentJob", ha_agent_job_class)

      # Test combined direct tools and delegated intents
      llm_response = {
        "direct_tool_calls" => [
          {
            "tool_name" => "rag_search",
            "parameters" => { "query" => "music discussion", "type" => "summaries" }
          }
        ],
        "tool_intents" => [
          {
            "tool" => "light.bedroom",
            "intent" => "Dim the bedroom lights"
          }
        ]
      }

      result = ConversationNewOrchestrator::ActionExecutor.call(
        llm_response: llm_response,
        session_id: session_id,
        conversation_id: session_id,
        user_message: "test message"
      )

      expect(result.success?).to be true
      expect(result.data[:sync_results]).to have_key("rag_search")
      expect(result.data[:delegated_intents]).to include(
        hash_including("tool" => "light.bedroom")
      )
    end
  end

  describe "Integration with Tool Analysis" do
    it "properly categorizes tools in analysis" do
      # This replaces the tool analysis test from the old spec
      mock_state = {
        action_results: {
          sync_results: {
            "rag_search" => { success: true, results: [] },
            "weather_tool" => { success: true, data: {} }
          },
          delegated_intents: [
            { "tool" => "light.living_room", "intent" => "test" }
          ]
        }
      }

      finalizer = ConversationNewOrchestrator::Finalizer.new(state: mock_state, user_message: "test")
      tool_analysis = finalizer.send(:analyze_tools)

      expect(tool_analysis[:sync_tools]).to include("rag_search", "weather_tool")
      expect(tool_analysis[:async_tools]).to include("light.living_room")
      expect(tool_analysis[:query_tools]).to be_empty # no memory_search tools
      expect(tool_analysis[:action_tools]).to include("weather_tool") # excludes rag_search
    end
  end

  describe "Full Action Execution Flow", skip: "Complex integration test requiring extensive HA mocking" do
    before do
      # Create a conversation for the integration test
      setup_result = ConversationNewOrchestrator::Setup.call(session_id: session_id, context: context)
      expect(setup_result.success?).to be true
    end

    it "executes actions and formats response correctly" do
      # Test that action execution integrates properly with the full orchestrator
      message = "Search for fire spinning events and make the lights orange"

      # Mock the LLM response to include both sync and async tools
      mock_ai_response = {
        speech_text: "I'll search for fire spinning events and adjust the lights!",
        continue_conversation: true,
        direct_tool_calls: [
          {
            "tool_name" => "rag_search",
            "parameters" => { "query" => "fire spinning", "type" => "events", "limit" => 3 }
          }
        ],
        tool_intents: [
          {
            "tool" => "light.living_room",
            "intent" => "Make lights warm orange like fire"
          }
        ]
      }

      # Mock the response synthesis to return our mock AI response
      allow_any_instance_of(ConversationNewOrchestrator::ResponseSynthesizer)
        .to receive(:call).and_return(ServiceResult.success({ ai_response: mock_ai_response }))

      # Create and run the orchestrator
      orchestrator = ConversationNewOrchestrator.new(
        session_id: session_id,
        message: message,
        context: context
      )

      hass_response = orchestrator.call

      # Verify the response structure includes both sync and async tool results
      expect(hass_response[:continue_conversation]).to be true
      expect(hass_response[:response_type]).to eq("action_done") # Has async tools

      # Check that the conversation log was created with proper tool tracking
      conversation = Conversation.find_by(session_id: session_id)
      expect(conversation).to be_present

      log = conversation.conversation_logs.last
      expect(log).to be_present

      metadata = JSON.parse(log.metadata)
      expect(metadata["sync_tools"]).to include("rag_search")
      expect(metadata["async_tools"]).to include("light.living_room")
    end
  end
end
