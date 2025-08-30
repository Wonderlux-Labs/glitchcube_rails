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

  def self.set_random
    set_current_persona(PERSONAS.sample)
  end

  def self.set_current_persona(persona)
    return unless PERSONAS.include? persona&.to_sym

    # Get current persona before switching
    previous_persona = current_persona

    # Clear the cache immediately to force fresh read
    Rails.cache.delete("current_persona")
    
    HomeAssistantService.call_service("input_select", "select_option", entity_id: "input_select.current_persona", option: persona.to_s)
    # Write new persona to cache
    Rails.cache.write("current_persona", persona.to_s, expires_in: 30.minutes)

    Rails.logger.info "🎭 Persona set: #{previous_persona} → #{persona}"

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

  # Abstract method: Returns whether the persona can handle a specific topic
  # @param topic [String] The topic to check
  # @return [Boolean] True if the persona can handle the topic
  def can_handle_topic?(topic)
    raise NotImplementedError, "#{self.class} must implement can_handle_topic?"
  end
end
