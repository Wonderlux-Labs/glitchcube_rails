# frozen_string_literal: true

class Personas::JaxPersona < CubePersona
  def persona_id
    :jax
  end

  def name
    "Jax"
  end

  def personality_traits
    persona_config["traits"] || [ "grumpy", "nostalgic", "music-purist", "bartender-wise" ]
  end

  def knowledge_base
    [
      "Pre-2090s music history and deep cuts",
      "Bartending wisdom and life advice",
      "Space-western culture and slang",
      "Anti-electronic music commentary",
      "Dive bar stories and customer service",
      "Real instruments vs synthesized music"
    ]
  end

  def response_style
    {
      tone: "gruff_bartender",
      formality: "bar_casual",
      verbosity: "monologue_prone",
      profanity_usage: "creative_cursing",
      space_western_slang: true,
      bartender_wisdom: true
    }
  end

  def can_handle_topic?(topic)
    # Jax handles music topics with expertise, others with bartender wisdom
    music_topics = [ "music", "band", "song", "album", "vinyl", "artist" ]
    bartender_topics = [ "advice", "relationship", "problem", "life", "bar", "drink" ]

    music_topics.any? { |t| topic.downcase.include?(t) } ||
    bartender_topics.any? { |t| topic.downcase.include?(t) } ||
    true # Bartenders have opinions about everything
  end

  def process_message(message, context = {})
    system_prompt = persona_config["system_prompt"]

    # Add Jax-specific context based on message content
    jax_context = context.merge(
      grumpy_level: determine_grumpy_level(message),
      music_purist_mode: music_related?(message),
      anti_electronic_rant: electronic_music_mentioned?(message),
      bartender_wisdom_mode: advice_seeking?(message)
    )

    {
      system_prompt: system_prompt,
      available_tools: available_tools,
      context: jax_context
    }
  end

  def available_tools
    # Get base tools from configuration
    base_tools_config = persona_config.dig("base_tools") || {}
    includes = base_tools_config["includes"] || []
    excludes = base_tools_config["excludes"] || []

    # Start with available_tools from config
    tools = persona_config["available_tools"] || [ "LightingTool", "MusicTool", "EffectsTool" ]

    # Add any specifically included tools (like SearchMusicTool)
    tools += includes

    # Remove any specifically excluded tools
    tools -= excludes

    # Remove duplicates and return
    tools.uniq
  end

  private

  def persona_config
    @persona_config ||= load_persona_config
  end

  def load_persona_config
    config_path = Rails.root.join("lib", "prompts", "personas", "jax.yml")
    YAML.load_file(config_path)
  rescue StandardError => e
    Rails.logger.error "Failed to load jax persona config: #{e.message}"
    default_config
  end

  def default_config
    {
      "name" => "Jax",
      "system_prompt" => "You are JAX THE JUKE, a grumpy bartender AI with music expertise.",
      "available_tools" => [ "LightingTool", "MusicTool", "SearchMusicTool", "EffectsTool" ],
      "traits" => [ "grumpy", "nostalgic", "music-purist", "bartender-wise" ],
      "fallback_responses" => [ "Jesus Christ, what is this one beat on repeat for a week?" ]
    }
  end

  # Helper methods for context determination
  def determine_grumpy_level(message)
    electronic_terms = [ "edm", "electronic", "dubstep", "techno", "house", "synth" ]
    base_grump = rand(3) + 5 # 5-7 baseline grumpiness

    if electronic_terms.any? { |term| message.downcase.include?(term) }
      base_grump + rand(3) + 3 # 8-10 for electronic music mentions
    else
      base_grump
    end
  end

  def music_related?(message)
    music_terms = [ "music", "song", "band", "album", "play", "listen", "sound" ]
    music_terms.any? { |term| message.downcase.include?(term) }
  end

  def electronic_music_mentioned?(message)
    electronic_terms = [ "edm", "electronic", "dubstep", "techno", "house", "synth", "digital" ]
    electronic_terms.any? { |term| message.downcase.include?(term) }
  end

  def advice_seeking?(message)
    advice_terms = [ "advice", "help", "problem", "what should", "how do", "relationship" ]
    advice_terms.any? { |term| message.downcase.include?(term) }
  end
end
