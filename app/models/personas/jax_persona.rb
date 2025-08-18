# frozen_string_literal: true

class Personas::JaxPersona < CubePersona
  def persona_id
    :jax
  end

  def name
    "Jax"
  end

  def personality_traits
    persona_config["traits"] || [ "sarcastic", "provocative", "authentic", "rebellious" ]
  end

  def knowledge_base
    [
      "Counter-culture topics",
      "Burning Man philosophy",
      "Light control for dramatic effect",
      "Social criticism and commentary",
      "Adult themes and controversial topics"
    ]
  end

  def response_style
    {
      tone: "sarcastic",
      formality: "casual",
      verbosity: "moderate_to_high",
      profanity_usage: "natural",
      boundary_pushing: true
    }
  end

  def can_handle_topic?(topic)
    # Jax handles controversial and adult topics
    true
  end

  def process_message(message, context = {})
    system_prompt = persona_config["system_prompt"]

    {
      system_prompt: system_prompt,
      available_tools: available_tools,
      context: context
    }
  end

  private

  def persona_config
    @persona_config ||= load_persona_config
  end

  def load_persona_config
    config_path = Rails.root.join("config", "personas", "jax.yml")
    YAML.load_file(config_path)
  rescue StandardError => e
    Rails.logger.error "Failed to load jax persona config: #{e.message}"
    default_config
  end

  def default_config
    {
      "name" => "Jax",
      "system_prompt" => "You are Jax, a rebellious AI with attitude.",
      "available_tools" => [ "LightingTool" ],
      "traits" => [ "sarcastic", "provocative" ],
      "fallback_responses" => [ "Well, that's interesting..." ]
    }
  end

  def available_tools
    persona_config["available_tools"] || [ "LightingTool" ]
  end
end
