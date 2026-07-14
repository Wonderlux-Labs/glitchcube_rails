# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Action Execution Integration", type: :integration do
  # Test the new ConversationOrchestrator action execution functionality
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
    let(:orchestrator) { ConversationOrchestrator.new(session_id: session_id, message: "test message", context: context) }

    it "splits the brain's channels into the sound lane and the main lane" do
      allow(EnvironmentDirectorJob).to receive(:perform_later)

      result = ConversationOrchestrator::ActionExecutor.call(
        llm_response: {
          "lights" => "Turn the lights orange",
          "sound" => "play heavy metal"
        },
        session_id: session_id,
        conversation_id: session_id,
        user_message: "make it spooky"
      )

      expect(result.success?).to be true
      # `sound` → audio agent lane
      expect(EnvironmentDirectorJob).to have_received(:perform_later).with(
        hash_including(instruction: "play heavy metal", convo_prefix: "cube_sound")
      )
      # everything else → main action agent lane
      expect(EnvironmentDirectorJob).to have_received(:perform_later).with(
        hash_including(instruction: "lights: Turn the lights orange", convo_prefix: "cube_env")
      )
      expect(result.data[:dispatched_environment]).to be true
    end
  end

  describe "Integration with Tool Analysis" do
    it "reports environment dispatch (persona turn runs no sync tools)" do
      mock_state = {
        action_results: {
          sync_results: {},
          dispatched_environment: true
        }
      }

      finalizer = ConversationOrchestrator::Finalizer.new(state: mock_state, user_message: "test")
      tool_analysis = finalizer.send(:analyze_tools)

      expect(tool_analysis[:sync_tools]).to eq([])
      expect(tool_analysis[:environment_dispatched]).to be true
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
