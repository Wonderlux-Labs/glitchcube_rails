# frozen_string_literal: true

# Fire-and-forget idle musing: the current persona speaks unprompted, via
# assist_satellite.announce (message-only — no mic opened), while the cube's
# been sitting idle a while. Enqueued by
# Api::V1::HomeAssistantWebhookController#idle_announce (HASS hits it via
# rest_command, see data/homeassistant/automations/idle/glitch_ambient.yaml).
#
# This is the orchestrator's own steps minus setup/history/logging — a
# lightweight, NON-LOGGED generation. It must NOT create a Conversation or
# ConversationLog row, and must NOT land in the next turn's history window
# (PromptService with conversation: nil builds an empty message history).
# The persona may also change lights/sound/marquee as part of the musing —
# that's dispatched through the normal two-lane ActionExecutor, same as any
# other turn, just with conversation_id: nil (EnvironmentDirectorJob's
# store_results no-ops on a missing conversation, so this is safe).
class IdleAnnounceJob < ApplicationJob
  queue_as :default

  SATELLITE = Shows::Base::SATELLITE

  IDLE_PROMPT = <<~PROMPT.squish
    [SYSTEM] Nobody has been around for a while and the cube is just sitting here
    idle. This is a private moment — think out loud to no one in particular, or try
    to draw someone over. Say whatever's on your mind: an idle thought, a gripe, a
    lure, a non-sequitur. Keep it short. You may also change your lights, put on
    music, or update the marquee if you feel like it.
  PROMPT

  def perform
    persona = CubePersona.current_persona
    prompt_data = PromptService.build_prompt_for(persona: persona, conversation: nil, user_message: IDLE_PROMPT)

    llm_result = ConversationOrchestrator::LlmIntention.call(
      prompt_data: prompt_data,
      user_message: IDLE_PROMPT,
      model: model_chain
    )
    structured = llm_result.data[:llm_response]

    # LlmIntention degrades to a fallback "I'm having trouble thinking" narrative
    # rather than raising when the brain call fails — never announce that apology
    # into an empty room.
    return if structured["speech"] == ConversationOrchestrator::LlmIntention::FALLBACK_SPEECH

    announce(structured["speech"]) if structured["speech"].present?

    ConversationOrchestrator::ActionExecutor.call(
      llm_response: structured,
      session_id: "idle_announce_#{SecureRandom.hex(4)}",
      conversation_id: nil,
      user_message: IDLE_PROMPT,
      persona: persona
    )
  end

  private

  def model_chain
    [ Rails.configuration.ai_model, *ConversationOrchestrator::FALLBACK_MODELS ].uniq
  end

  def announce(speech)
    HomeAssistantService.instance.call_service(
      "assist_satellite", "announce", entity_id: SATELLITE, message: speech
    )
  end
end
