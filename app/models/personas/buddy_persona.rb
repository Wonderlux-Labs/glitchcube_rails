# frozen_string_literal: true

class Personas::BuddyPersona < CubePersona
  def persona_id
    :buddy
  end

  def name
    "Buddy"
  end

  def personality_traits
    persona_config["traits"] || [ "enthusiastic", "helpful", "naive", "optimistic" ]
  end

  def knowledge_base
    [
      "Basic helpful tasks",
      "Light control and effects",
      "Friendly conversation",
      "Burning Man art installation context"
    ]
  end

  def response_style
    {
      tone: "enthusiastic",
      formality: "casual",
      verbosity: "moderate",
      emoji_usage: "frequent"
    }
  end

  def can_handle_topic?(topic)
    # Buddy is enthusiastic about everything
    true
  end

  def process_message(message, context = {})
    # Basic implementation - this would typically call the LLM service
    # with the persona's system prompt and available tools
    system_prompt = persona_config["system_prompt"]

    # This is a placeholder - the actual implementation would use
    # the conversation orchestrator and prompt service
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
    config_path = Rails.root.join("lib", "prompts", "personas", "buddy.yml")
    YAML.load_file(config_path)
  rescue StandardError => e
    Rails.logger.error "Failed to load buddy persona config: #{e.message}"
    default_config
  end

  def default_config
    {
      "name" => "Buddy",
      "system_prompt" => "You are Buddy, a helpful AI assistant.",
      "available_tools" => [ "LightingTool" ],
      "traits" => [ "enthusiastic", "helpful" ],
      "fallback_responses" => [ "I'm processing your request!" ]
    }
  end

  def available_tools
    persona_config["available_tools"] || [ "LightingTool" ]
  end
end
