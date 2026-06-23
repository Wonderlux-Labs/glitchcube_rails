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

    it "dispatches environment intents to the single translator job" do
      allow(EnvironmentDirectorJob).to receive(:perform_later)

      # Test delegation of environment intents
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
      # All environment changes go through one translator (no per-domain fan-out)
      expect(EnvironmentDirectorJob).to have_received(:perform_later).with(
        hash_including(instruction: "Make lights warm and orange like fire")
      )
    end

    it "dispatches a single environment_instruction directly" do
      allow(EnvironmentDirectorJob).to receive(:perform_later)

      result = ConversationNewOrchestrator::ActionExecutor.call(
        llm_response: { "environment_instruction" => "Turn the lights orange and play heavy metal" },
        session_id: session_id,
        conversation_id: session_id,
        user_message: "make it spooky"
      )

      expect(result.success?).to be true
      expect(EnvironmentDirectorJob).to have_received(:perform_later).with(
        hash_including(instruction: "Turn the lights orange and play heavy metal")
      )
    end

    it "handles mixed sync and async tools" do
      allow(EnvironmentDirectorJob).to receive(:perform_later)

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

  # NOTE: a skipped "Full Action Execution Flow" integration test was removed here.
  # It mocked the old narrative-response shape (`tool_intents` + per-domain
  # `direct_tool_calls`) and asserted per-domain `async_tools` metadata from the
  # removed agent fan-out. The current pipeline emits a single plain-English
  # `environment_instruction` dispatched via EnvironmentDirectorJob (covered by
  # spec/jobs/environment_director_job_spec.rb), so those expectations no longer
  # describe real behavior.
end
