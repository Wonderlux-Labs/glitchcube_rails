# app/jobs/environment_director_job.rb
#
# Offloads the brain's `actions` to a Home Assistant conversation agent (an LLM
# with the Assist API enabled). We send the plain-English action text; the agent
# owns ALL of the tool-calling — picking devices, resolving "romantic lights" to
# RGB, retrying — and replies in natural language. That reply is stored on the
# conversation as `pending_ha_results` so the next turn's PromptBuilder folds the
# outcome back into the brain's context (speak-first, act-async: this runs while
# the current speech is being read aloud, so the result is usually back by the
# next turn).
#
# This replaces the old in-Rails translator (ToolCallingService + Tools::Registry).
#
# One job runs per LANE (see ConversationOrchestrator::ActionExecutor): the `sound`
# channel goes to the audio agent, everything else to the main action agent, and both
# run in parallel. `agent_id` and `convo_prefix` are passed per lane so each agent keeps
# its OWN running context and the two don't stomp each other. Both append to the
# conversation's `pending_ha_results`, so whichever finishes first (or at all) still
# lands in the next turn's prompt — order doesn't matter.
class EnvironmentDirectorJob < ApplicationJob
  queue_as :default

  def perform(instruction:, session_id:, conversation_id:, user_message:, persona: nil,
              agent_id: nil, convo_prefix: "cube_env")
    agent_id ||= Rails.configuration.hass_action_agent
    Rails.logger.info "🎬 EnvironmentDirectorJob [#{convo_prefix}] → #{agent_id}: #{instruction}"

    response = HomeAssistantService.instance.conversation_process(
      text: instruction,
      agent_id: agent_id,
      # Stable per-lane, per-conversation id so each agent keeps its own running context
      # of what it has already done for this cube conversation.
      conversation_id: "#{convo_prefix}_#{conversation_id}"
    )

    reply = extract_agent_reply(response)
    Rails.logger.info "🏠 Action agent replied: #{reply}"
    ConversationLogger.ha_agent_reply(instruction, reply, persona: persona)

    store_results(
      conversation_id: conversation_id,
      user_message: user_message,
      instruction: instruction,
      result: reply,
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

  # HASS /api/conversation/process returns the agent's spoken reply at
  # response.speech.plain.speech. Fall back to any error text or the raw body.
  def extract_agent_reply(response)
    return response if response.is_a?(String)
    return nil unless response.is_a?(Hash)

    response.dig("response", "speech", "plain", "speech") ||
      response.dig(:response, :speech, :plain, :speech) ||
      response["error"] || response[:error] ||
      response.to_s
  end

  # Append to conversation.metadata_json["pending_ha_results"] so the next
  # conversation turn can inject the outcome (PromptBuilder#inject_previous_ha_results).
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
      ha_response: result,
      error: error,
      processed: false
    }

    conversation.update!(metadata_json: metadata.merge("pending_ha_results" => pending))
  end
end
