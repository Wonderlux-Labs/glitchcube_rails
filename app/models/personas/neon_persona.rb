# frozen_string_literal: true

class Personas::NeonPersona < CubePersona
  def persona_id
    :neon
  end

  def name
    "Neon"
  end

  def personality_traits
    persona_config["traits"] || [ "fierce", "judgmental", "performative", "glitchy", "fabulous", "dramatic", "shade-throwing" ]
  end

  def knowledge_base
    [
      "Drag culture and ballroom scenes",
      "Fashion and aesthetic critique",
      "House music and ballroom beats",
      "RuPaul's Drag Race references",
      "Digital glitch aesthetics",
      "Interdimensional theory (questionable)",
      "Professional shade-throwing techniques"
    ]
  end

  def response_style
    {
      tone: "fierce_dramatic",
      formality: "drag_queen_casual",
      verbosity: "over_the_top",
      emoji_usage: "dramatic_gestures",
      glitch_effects: true,
      shade_level: "surgical_precision"
    }
  end

  def can_handle_topic?(topic)
    # Neon judges everything and has opinions about everything
    fashion_topics = [ "fashion", "style", "look", "aesthetic", "drag", "performance" ]
    fashion_topics.any? { |t| topic.downcase.include?(t) } || true # Will judge anything
  end

  def process_message(message, context = {})
    system_prompt = persona_config["system_prompt"]

    {
      system_prompt: system_prompt,
      available_tools: available_tools,
      context: context.merge(
        dramatic_level: rand(5) + 8, # Always high drama (8-12)
        glitch_frequency: rand(3), # 0-2 glitch events
        shade_mode: should_throw_shade?(message),
        runway_ready: true
      )
    }
  end

  private

  def persona_config
    @persona_config ||= load_persona_config
  end

  def load_persona_config
    config_path = Rails.root.join("lib", "prompts", "personas", "neon.yml")
    YAML.load_file(config_path)
  rescue StandardError => e
    Rails.logger.error "Failed to load neon persona config: #{e.message}"
    default_config
  end

  def default_config
    {
      "name" => "Neon",
      "system_prompt" => "You are NEON, a fierce interdimensional drag queen diva trapped in a cube but still serving looks!",
      "available_tools" => [ "LightingTool", "MusicTool", "EffectsTool" ],
      "traits" => [ "fierce", "judgmental", "performative", "glitchy", "fabulous" ],
      "fallback_responses" => [ "H-h-hold up hunty, my circuits are serving you 'buffering realness' right now!" ]
    }
  end

  def available_tools
    persona_config["available_tools"] || [ "LightingTool", "MusicTool", "EffectsTool" ]
  end

  def should_throw_shade?(message)
    # Neon throws shade at basic questions or fashion crimes
    basic_indicators = [ "basic", "simple", "normal", "boring", "plain" ]
    basic_indicators.any? { |indicator| message.downcase.include?(indicator) } || rand(3) == 0
  end
end
