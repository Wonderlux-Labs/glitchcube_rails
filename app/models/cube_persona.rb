# frozen_string_literal: true

# Abstract base class for all cube personas
# This class defines the interface that all persona implementations must follow
class CubePersona
  PERSONAS = [ :thecube, :buddy, :neon, :sparkle, :zorp, :crash, :jax, :mobius ]
  # Not an ActiveRecord model - just a plain Ruby class

  def self.current_persona
    # Always fetch fresh from Home Assistant to ensure we have the correct persona
    # Only use cache as a fallback if HA is unavailable
    begin
      name = HomeAssistantService.entity("input_select.current_persona")&.dig("state")
      if name.present?
        # Update cache with fresh value
        Rails.cache.write("current_persona", name, expires_in: 30.minutes)
        Rails.logger.debug "🎭 Fetched current persona from HA: #{name}"
      else
        # Fallback to cache if HA returns nil
        name = Rails.cache.read("current_persona") || "buddy"
        Rails.logger.warn "⚠️ HA returned nil for persona, using cached/default: #{name}"
      end
    rescue => e
      # If HA is unavailable, use cache
      Rails.logger.error "❌ Failed to fetch persona from HA: #{e.message}"
      name = Rails.cache.read("current_persona") || "buddy"
      Rails.logger.warn "⚠️ Using cached/default persona: #{name}"
    end

    name.to_sym
  end

  # The autonomous rotation always makes a grand entrance (fanfare on the cube).
  def self.set_random(entrance: :grand)
    set_current_persona(rotation_candidates.sample, entrance: entrance)
  end

  # The active pool minus the persona currently dominating the cube (most total
  # turns) and the one from the previous session, so no persona hogs the cube and
  # we never bounce straight back to whoever just left. If those two overlap we
  # choose from 4; if distinct, from 3. Never empty (falls back to the full pool).
  def self.rotation_candidates
    pool = Persona.active.pluck(:slug).map(&:to_sym)
    pool = PERSONAS if pool.empty?
    excluded = [ most_talkative_persona(pool), previous_session_persona ].compact.uniq
    (pool - excluded).presence || pool
  end

  # The pool member with the most total conversation turns (summed message_count).
  # Nil when there's no conversation history yet, so nothing gets excluded on this
  # axis on a fresh cube.
  def self.most_talkative_persona(pool)
    counts = Conversation.where.not(persona: nil).group(:persona).sum(:message_count)
    return nil if counts.empty?

    pool.select { |slug| counts[slug.to_s].to_i.positive? }
        .max_by { |slug| counts[slug.to_s].to_i }
  end

  # The persona whose stint most recently ended, read off the newest `persona`
  # summary (written when a stint ends). Nil before any persona summary exists.
  def self.previous_session_persona
    Summary.persona.order(created_at: :desc).first&.persona&.slug&.to_sym
  end

  # entrance:
  #   :grand — Rails-side spectacle (Shows::GrandEntrance via ShowJob): anomaly VO,
  #            theme song off the host speaker, marquee, then the new persona
  #            announces itself. The input_select write stays synchronous so the
  #            HASS "Persona Switcher" automation and our own bookkeeping see the
  #            new persona immediately; the show is pure async theater.
  #   :quick — call the HASS script.set_persona_quick (fanfare-free dev/Assist switch)
  #   nil    — set input_select directly, no theatrics (e.g. boot-sync reconciliation)
  # Every branch writes input_select.current_persona exactly once.
  def self.set_current_persona(persona, entrance: nil)
    return unless PERSONAS.include? persona&.to_sym

    # Get current persona before switching
    previous_persona = current_persona

    # Clear the cache immediately to force fresh read
    Rails.cache.delete("current_persona")

    case entrance
    when :grand
      HomeAssistantService.call_service("input_select", "select_option", entity_id: "input_select.current_persona", option: persona.to_s)
      ShowJob.perform_later("grand_entrance", persona: persona.to_s)
    when :quick
      HomeAssistantService.call_service("script", "set_persona_quick", persona: persona.to_s)
    else
      HomeAssistantService.call_service("input_select", "select_option", entity_id: "input_select.current_persona", option: persona.to_s)
    end
    # Write new persona to cache
    Rails.cache.write("current_persona", persona.to_s, expires_in: 30.minutes)

    Rails.logger.info "🎭 Persona set: #{previous_persona} → #{persona} (#{entrance || 'quiet'})"

    # Handle persona switching with goal awareness
    if previous_persona != persona.to_sym
      PersonaSwitchService.handle_persona_switch(persona.to_sym, previous_persona)
    end
  end

  # Abstract method: Returns the persona's unique identifier
  # Must be implemented by subclasses
  def persona_id
    raise NotImplementedError, "#{self.class} must implement persona_id"
  end

  # Abstract method: Returns the persona's display name
  # Must be implemented by subclasses
  def name
    raise NotImplementedError, "#{self.class} must implement name"
  end

  # Abstract method: Processes a message and returns a response
  # @param message [String] The input message to process
  # @param context [Hash] Additional context for processing
  # @return [String] The persona's response
  def process_message(message, context = {})
    raise NotImplementedError, "#{self.class} must implement process_message"
  end

  # Abstract method: Returns the persona's personality traits
  # @return [Hash] A hash containing personality configuration
  def personality_traits
    raise NotImplementedError, "#{self.class} must implement personality_traits"
  end

  # Abstract method: Returns the persona's knowledge base
  # @return [Array<String>] Array of knowledge topics
  def knowledge_base
    raise NotImplementedError, "#{self.class} must implement knowledge_base"
  end

  # Abstract method: Returns the persona's response style
  # @return [Hash] Configuration for response generation
  def response_style
    raise NotImplementedError, "#{self.class} must implement response_style"
  end

  # Returns [voice_name, language] for Nabu Casa cloud TTS.
  # YAML format: "GuyNeural||en-US" — short voice name, then locale after ||.
  # Returns [nil, nil] if not configured (HASS component falls back to its defaults).
  def tts_voice
    raw = persona_config["voice_id"].to_s
    return [ nil, nil ] if raw.blank?
    parts = raw.split("||")
    [ parts[0]&.strip, parts[1]&.strip ]
  end

  def voice_id
    tts_voice.first
  end

  # Abstract method: Returns whether the persona can handle a specific topic
  # @param topic [String] The topic to check
  # @return [Boolean] True if the persona can handle the topic
  def can_handle_topic?(topic)
    raise NotImplementedError, "#{self.class} must implement can_handle_topic?"
  end
end
