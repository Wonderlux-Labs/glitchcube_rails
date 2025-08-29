# frozen_string_literal: true

module ConversationOrchestratorHelpers
  # Mock helpers for ConversationNewOrchestrator
  # Based on the actual Finalizer.format_for_hass structure

  def mock_orchestrator_success(speech_text: "Test response", continue_conversation: false, async_tools: [], sync_tools: [])
    # ConversationNewOrchestrator returns the hass_response hash directly
    build_hass_response(
      speech_text: speech_text,
      continue_conversation: continue_conversation,
      async_tools: async_tools,
      sync_tools: sync_tools
    )
  end

  def mock_orchestrator_failure(error_message: "Test error")
    ServiceResult.failure(error_message)
  end

  def stub_orchestrator_call(result)
    allow_any_instance_of(ConversationNewOrchestrator).to receive(:call).and_return(result)
  end

  # Helper to create response structure that matches controller expectations
  def build_legacy_mock_response(speech_text:, continue_conversation: false, **extra_fields)
    {
      continue_conversation: continue_conversation,
      end_conversation: !continue_conversation,  # Add this so controller logic works correctly
      response: {
        speech: {
          plain: {
            speech: speech_text
          }
        }
      }
    }.merge(extra_fields)
  end

  private

  def build_hass_response(speech_text:, continue_conversation:, async_tools: [], sync_tools: [])
    # This matches the structure from ConversationResponse.to_home_assistant_response
    {
      continue_conversation: continue_conversation,
      response: {
        response_type: async_tools.any? ? "action_done" : "query_answer",
        language: "en",
        data: {
          targets: (sync_tools + async_tools).map { |tool|
            { entity_id: tool, name: tool.humanize, domain: tool.split(".").first }
          },
          success: async_tools.map { |tool|
            { entity_id: tool, name: tool.humanize, state: "pending" }
          },
          failed: []
        },
        speech: {
          plain: {
            speech: speech_text
          }
        }
      },
      conversation_id: "test_session",
      # Additional field that Finalizer adds
      end_conversation: !continue_conversation
    }
  end
end

RSpec.configure do |config|
  config.include ConversationOrchestratorHelpers
end
