# app/services/conversation_orchestrator/action_executor.rb
class ConversationOrchestrator::ActionExecutor
  def self.call(llm_response:, session_id:, conversation_id:, user_message:, persona: nil)
    new(llm_response: llm_response, session_id: session_id, conversation_id: conversation_id, user_message: user_message, persona: persona).call
  end

  def initialize(llm_response:, session_id:, conversation_id:, user_message:, persona: nil)
    @output = llm_response || {}
    @session_id = session_id
    @conversation_id = conversation_id
    @user_message = user_message
    @persona = persona
  end

  def call
    dispatched = dispatch_intents

    ServiceResult.success({
      sync_results: {},
      dispatched_environment: dispatched
    })
  rescue => e
    ServiceResult.failure("Action execution failed: #{e.message}")
  end

  private

  NARRATIVE_KEYS = Schemas::NarrativeResponseSchema::NARRATIVE_KEYS

  # The brain returns plain-English action channels as top-level keys, e.g.
  # { "lights" => "body deep purple", "sound" => "play some jazz", "marquee" => "HI" }.
  # We split them into two lanes and dispatch both in parallel:
  #   - the `sound` channel → the audio/jukebox agent (slower, more iterative);
  #   - everything else (lights, marquee, other_actions, and ANY other non-narrative
  #     key) → the main action agent, joined into one labeled instruction.
  # If the output isn't a parseable hash of channels, we fall back to dumping whatever
  # we got straight at the main agent. Returns true if anything was dispatched.
  def dispatch_intents
    return dispatch_fallback unless @output.is_a?(Hash)

    channels = @output.reject { |k, v| NARRATIVE_KEYS.include?(k.to_s) || v.blank? }
                      .transform_keys(&:to_s)
    return false if channels.empty?

    dispatched = false

    # Sound lane → audio agent.
    if (sound = channels["sound"]).present?
      dispatch(instruction: sound.to_s,
               agent_id: Rails.configuration.hass_sound_agent,
               convo_prefix: "cube_sound")
      dispatched = true
    end

    # Everything else → main action agent, as one labeled, multi-line instruction so the
    # agent can tell the channels apart (e.g. "lights: ...\nmarquee: ...").
    rest = channels.except("sound")
    if rest.any?
      instruction = rest.map { |k, v| "#{k}: #{v}" }.join("\n")
      dispatch(instruction: instruction,
               agent_id: Rails.configuration.hass_action_agent,
               convo_prefix: "cube_env")
      dispatched = true
    end

    dispatched
  end

  # Super-weird output (not a channel hash): hand the raw thing to the main agent so we
  # never silently drop an intent.
  def dispatch_fallback
    raw = @output.to_s.presence
    return false if raw.blank?

    dispatch(instruction: raw, agent_id: Rails.configuration.hass_action_agent, convo_prefix: "cube_env")
    true
  end

  # Hand one lane's instruction to a Home Assistant conversation agent via
  # EnvironmentDirectorJob — speak first, act async.
  def dispatch(instruction:, agent_id:, convo_prefix:)
    Rails.logger.info "🎬 Dispatching [#{convo_prefix}] → #{agent_id}: #{instruction}"

    EnvironmentDirectorJob.perform_later(
      instruction: instruction,
      session_id: @session_id,
      conversation_id: @conversation_id,
      user_message: @user_message,
      persona: @persona.to_s.presence,
      agent_id: agent_id,
      convo_prefix: convo_prefix
    )
  end
end
