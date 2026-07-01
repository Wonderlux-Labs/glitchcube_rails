# frozen_string_literal: true

# Abstract base class for all cube personas
# This class defines the interface that all persona implementations must follow
class CubePersona
  # There is only one character now: the emergent artifact. Its identity is not a
  # fixed persona but the dynamic self-model (character sheet + beliefs). The roster
  # and the Home-Assistant persona switcher are gone.
  PERSONAS = [ :artifact ].freeze

  def self.current_persona
    :artifact
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
