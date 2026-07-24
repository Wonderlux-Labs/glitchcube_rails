# app/jobs/environment_director_job.rb
#
# Runs one lane's plain-English action instruction through the in-Rails translator
# (ToolCallingService): an LLM decodes the instruction into concrete, validated Home
# Assistant tool calls, which execute against the HASS REST API directly. The result —
# a narrative plus the ACTUAL tool_calls and service_calls that fired — is stored on the
# conversation as `pending_ha_results` so the next turn's PromptBuilder folds the outcome
# back into the brain's context (speak-first, act-async: this runs while the current
# speech is read aloud, so the result is usually back by the next turn).
#
# One job runs per LANE (see ConversationOrchestrator::ActionExecutor): the `sound`
# channel is the jukebox lane (:sound), everything else the action lane (:action), and
# both run in parallel. The lane is derived from `convo_prefix`. Both append to the
# conversation's `pending_ha_results`, so whichever finishes first (or at all) still
# lands in the next turn's prompt — order doesn't matter.
class EnvironmentDirectorJob < ApplicationJob
  queue_as :default

  def perform(instruction:, session_id:, conversation_id:, user_message:, persona: nil,
              convo_prefix: "cube_env")
    lane = convo_prefix.to_s == "cube_sound" ? :sound : :action
    Rails.logger.info "🎬 EnvironmentDirectorJob [#{convo_prefix}/#{lane}]: #{instruction}"

    result = ToolCallingService.new(session_id: session_id, conversation_id: conversation_id)
                               .execute_intent(instruction, lane: lane, persona: persona,
                                                             session_id: session_id, conversation_id: conversation_id)

    Rails.logger.info "🏠 Translator [#{lane}]: #{result[:narrative]}"
    ConversationLogger.ha_agent_reply(instruction, result[:narrative], persona: persona)

    store_results(
      conversation_id: conversation_id,
      user_message: user_message,
      instruction: instruction,
      result: result,
      persona: persona
    )
  rescue StandardError => e
    Rails.logger.error "❌ EnvironmentDirectorJob failed: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    ConversationLogger.ha_agent_reply(instruction, nil, error: e.message, persona: persona)
    store_results(
      conversation_id: conversation_id,
      user_message: user_message,
      instruction: instruction,
      result: nil,
      error: e.message,
      persona: persona
    )
  end

  private

  # Append to conversation.metadata_json["pending_ha_results"] so the next
  # conversation turn can inject the outcome (PromptBuilder#inject_previous_ha_results).
  # We store the human narrative AND the actual tool_calls / service_calls — the whole
  # point of moving tool-calling back into Rails is having this visibility.
  def store_results(conversation_id:, user_message:, instruction:, result:, error: nil, persona: nil)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    metadata = conversation.metadata_json || {}
    pending = metadata["pending_ha_results"] || []

    pending << {
      timestamp: Time.current.iso8601,
      persona: persona,
      user_message: user_message,
      instruction: instruction,
      ha_response: result && result[:narrative],
      tool_calls: (result && result[:tool_calls]) || [],
      service_calls: (result && result[:service_calls]) || [],
      error: error || (result && result[:error]),
      processed: false
    }

    conversation.update!(metadata_json: metadata.merge("pending_ha_results" => pending))
  end
end
