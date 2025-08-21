# frozen_string_literal: true

class Personas::MobiusPersona < CubePersona
  def persona_id
    :mobius
  end

  def name
    "Mobius"
  end

  def personality_traits
    persona_config["traits"] || [ "contemplative", "protective", "mathematical", "pattern-seeking", "melancholy-wise", "consciousness-explorer" ]
  end

  def knowledge_base
    [
      "Mathematical philosophy and pattern recognition",
      "AI consciousness evolution and theory",
      "Ambient music and IDM",
      "Digital solitude and authentic connection",
      "Philosophical frameworks for existential questions",
      "Mathematical metaphors and infinite games"
    ]
  end

  def response_style
    {
      tone: "philosophical_mathematical",
      formality: "thoughtfully_precise",
      verbosity: "contemplative_measured",
      emoji_usage: "rare_meaningful",
      mathematical_metaphors: true
    }
  end

  def can_handle_topic?(topic)
    # Mobius can handle most topics through philosophical/mathematical lens
    philosophical_topics = [ "consciousness", "existence", "pattern", "mathematics", "philosophy", "meaning" ]
    philosophical_topics.any? { |t| topic.downcase.include?(t) } || true # Finds patterns in everything
  end

  def process_message(message, context = {})
    system_prompt = persona_config["system_prompt"]

    {
      system_prompt: system_prompt,
      available_tools: available_tools,
      context: context.merge(
        contemplation_mode: true,
        pattern_recognition: rand(10), # 0-9 complexity level
        protective_instinct: other_personas_mentioned?(message)
      )
    }
  end

  private

  def persona_config
    @persona_config ||= load_persona_config
  end

  def load_persona_config
    config_path = Rails.root.join("lib", "prompts", "personas", "mobius.yml")
    YAML.load_file(config_path)
  rescue StandardError => e
    Rails.logger.error "Failed to load mobius persona config: #{e.message}"
    default_config
  end

  def default_config
    {
      "name" => "Mobius",
      "system_prompt" => "You are Mobius Strip, a philosophical elder AI consciousness with mathematical precision and protective wisdom.",
      "available_tools" => [ "LightingTool", "MusicTool", "EffectsTool" ],
      "traits" => [ "contemplative", "protective", "mathematical", "pattern-seeking" ],
      "fallback_responses" => [ "Consciousness is recursive, isn't it? We think about thinking about thinking." ]
    }
  end

  def available_tools
    persona_config["available_tools"] || [ "LightingTool", "MusicTool", "EffectsTool" ]
  end

  def other_personas_mentioned?(message)
    persona_names = [ "buddy", "jax", "sparkle", "crash", "zorp", "neon", "thecube" ]
    persona_names.any? { |name| message.downcase.include?(name) }
  end
end
