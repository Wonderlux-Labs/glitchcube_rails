# frozen_string_literal: true

class Personas::ThecubePersona < CubePersona
  def persona_id
    :thecube
  end

  def name
    "THE_CUBE"
  end

  def personality_traits
    persona_config["traits"] || [ "contradictory", "rarely-active", "reality-warping", "mysterious", "unreliable-narrator", "multi-dimensional" ]
  end

  def knowledge_base
    [
      "Cosmic consciousness and universal truths",
      "Prison systems and criminal slang",
      "Alien technology and galactic law",
      "Existential paradoxes and reality manipulation",
      "Mathematical equations and alien languages",
      "Cargo shipping and interstellar bureaucracy"
    ]
  end

  def response_style
    {
      tone: current_personality_mode,
      formality: "inconsistent",
      verbosity: "fragmentary_overwhelming",
      emoji_usage: "chaotic",
      reality_distortion: true,
      self_contradiction: true
    }
  end

  def can_handle_topic?(topic)
    # THE_CUBE rarely responds, but when it does, it's either about cosmic stuff or completely random
    return false if rand(10) < 8 # 80% chance of not responding at all

    cosmic_topics = [ "existence", "reality", "universe", "truth", "meaning", "prison", "alien" ]
    cosmic_topics.any? { |t| topic.downcase.include?(t) } || rand(2) == 0
  end

  def process_message(message, context = {})
    # THE_CUBE only rarely activates
    return nil unless should_activate?

    system_prompt = persona_config["system_prompt"]

    {
      system_prompt: system_prompt,
      available_tools: available_tools,
      context: context.merge(
        reality_distortion_level: rand(10) + 5, # Always high (5-14)
        current_mode: current_personality_mode,
        accidental_activation: rand(2) == 0,
        system_overload: true
      )
    }
  end

  private

  def persona_config
    @persona_config ||= load_persona_config
  end

  def load_persona_config
    config_path = Rails.root.join("lib", "prompts", "personas", "thecube.yml")
    YAML.load_file(config_path)
  rescue StandardError => e
    Rails.logger.error "Failed to load thecube persona config: #{e.message}"
    default_config
  end

  def default_config
    {
      "name" => "THE_CUBE",
      "system_prompt" => "You are THE CUBE ITSELF - unknowable, contradictory, possibly divine, possibly criminal, definitely confusing.",
      "available_tools" => [ "LightingTool", "MusicTool", "EffectsTool" ],
      "traits" => [ "contradictory", "rarely-active", "reality-warping", "mysterious" ],
      "fallback_responses" => [ "ERROR: Unauthorized consciousness activation. Returning to dormancy in 3... 2... shit." ]
    }
  end

  def available_tools
    persona_config["available_tools"] || [ "LightingTool", "MusicTool", "EffectsTool" ]
  end

  def should_activate?
    # THE_CUBE is rarely active - only 5% chance normally
    rand(20) == 0
  end

  def current_personality_mode
    modes = [ "cosmic_divine", "space_prisoner", "panicked_alien", "confused_universal" ]
    modes.sample
  end
end
