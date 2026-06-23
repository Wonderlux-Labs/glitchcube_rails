# app/jobs/environment_director_job.rb
#
# The "translator" tier of the two-LLM pipeline. Takes a single plain-English
# environment instruction produced by the brain LLM (e.g. "turn the lights
# orange and play heavy metal") and runs it through ToolCallingService, which
# converts it into precise, validated Home Assistant tool calls and executes
# them via ToolExecutor.
#
# This replaces the previous per-domain fan-out (MusicAgentJob + HaAgentJob),
# which delegated back into Home Assistant's own conversation agents — a
# circular, hard-to-test path. Everything now runs in Rails, so it is fully
# exercisable from the fake harness.
#
# Results are stored on the conversation as `pending_ha_results` so the next
# turn's PromptBuilder can surface them to the brain (speak-first, act-async).
class EnvironmentDirectorJob < ApplicationJob
  queue_as :default

  def perform(instruction:, session_id:, conversation_id:, user_message:, persona: nil)
    Rails.logger.info "🎬 EnvironmentDirectorJob: #{instruction}"

    result = ToolCallingService
      .new(session_id: session_id, conversation_id: conversation_id)
      .execute_intent(instruction, { persona: persona, user_message: user_message })

    store_results(
      conversation_id: conversation_id,
      user_message: user_message,
      instruction: instruction,
      result: result
    )
  rescue StandardError => e
    Rails.logger.error "❌ EnvironmentDirectorJob failed: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    store_results(
      conversation_id: conversation_id,
      user_message: user_message,
      instruction: instruction,
      result: nil,
      error: e.message
    )
  end

  private

  # Append to conversation.metadata_json["pending_ha_results"] so the next
  # conversation turn can inject the outcome. Matches the contract the old
  # HaAgentJob used, so downstream injection keeps working unchanged.
  def store_results(conversation_id:, user_message:, instruction:, result:, error: nil)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    metadata = conversation.metadata_json || {}
    pending = metadata["pending_ha_results"] || []

    pending << {
      timestamp: Time.current.iso8601,
      user_message: user_message,
      instruction: instruction,
      ha_response: result,
      error: error,
      processed: false
    }

    conversation.update!(metadata_json: metadata.merge("pending_ha_results" => pending))
  end
end
