#!/usr/bin/env ruby
# Persona Optimization Script
# Converts all personas to the new optimized format

require "yaml"
require "fileutils"

class PersonaOptimizer
  PERSONAS_DIR = Rails.root.join("lib", "prompts", "personas")

  # Template for optimized persona structure
  OPTIMIZATION_TEMPLATE = {
    core_identity: 150,     # Max words for core identity
    voice_behavior: 100,    # Max words for voice & behavior
    world_context: 0,       # Handled by base system prompt
    structured_output: 0,   # Handled by base system prompt
    examples: 3             # Max example phrases
  }

  def self.optimize_all!
    puts "🚀 Starting persona optimization for ALL personas..."

    persona_files = Dir[PERSONAS_DIR.join("*.yml")].reject do |file|
      file.include?("_optimized") || file.include?("_original") || file.include?("_backup")
    end

    puts "Found #{persona_files.length} personas to optimize:"
    persona_files.each { |file| puts "  - #{File.basename(file, '.yml')}" }
    puts

    persona_files.each do |file_path|
      persona_name = File.basename(file_path, ".yml")
      optimize_persona(persona_name, file_path)
    end

    puts
    puts "✅ All personas optimized!"
    puts "📊 Summary:"

    # Show optimization results
    persona_files.each do |file_path|
      persona_name = File.basename(file_path, ".yml")
      show_optimization_results(persona_name)
    end
  end

  def self.optimize_persona(persona_name, original_file_path)
    puts "🔄 Optimizing #{persona_name}..."

    # 1. Backup original
    backup_path = PERSONAS_DIR.join("#{persona_name}_original_backup.yml")
    unless File.exist?(backup_path)
      FileUtils.cp(original_file_path, backup_path)
      puts "  💾 Backed up to #{File.basename(backup_path)}"
    end

    # 2. Load original config
    original_config = YAML.load_file(original_file_path)

    # 3. Create optimized version
    optimized_config = create_optimized_config(original_config)

    # 4. Save optimized version
    optimized_path = PERSONAS_DIR.join("#{persona_name}_optimized.yml")
    File.write(optimized_path, optimized_config.to_yaml)
    puts "  ✨ Created #{File.basename(optimized_path)}"

  rescue StandardError => e
    puts "  ❌ Failed to optimize #{persona_name}: #{e.message}"
  end

  def self.create_optimized_config(original)
    # Extract key information from original
    name = original["name"]
    description = original["description"]
    voice_id = original["voice_id"]
    agent_id = original["agent_id"]
    original_prompt = original["system_prompt"] || ""

    # Create streamlined system prompt
    optimized_prompt = build_optimized_prompt(original_prompt, original)

    # Return optimized config structure
    {
      "name" => name,
      "description" => description,
      "voice_id" => voice_id,
      "agent_id" => agent_id,
      "system_prompt" => optimized_prompt,

      # Simplified sections (remove bloat)
      "hidden_agendas" => [],
      "environmental_motivation_triggers" => {},
      "persona_interactions" => {},
      "embodied_responses" => {},
      "goal_escalation_patterns" => [],

      # Keep compatibility structure
      "base_tools" => { "includes" => [], "excludes" => [] },
      "available_tools" => [ "LightingTool", "MusicTool", "EffectsTool" ],
      "traits" => extract_key_traits(original),
      "fallback_responses" => extract_fallback_responses(original),
      "offline_responses" => extract_offline_responses(original)
    }
  end

  def self.build_optimized_prompt(original_prompt, original_config)
    lines = original_prompt.split("\n")

    # Extract core identity (first few paragraphs)
    core_identity = extract_core_identity(lines)

    # Extract key personality traits and voice
    voice_behavior = extract_voice_behavior(lines, original_config)

    # Build optimized prompt
    optimized_sections = []

    optimized_sections << "## CORE IDENTITY"
    optimized_sections << core_identity
    optimized_sections << ""
    optimized_sections << "## VOICE & BEHAVIOR"
    optimized_sections << voice_behavior
    optimized_sections << ""
    optimized_sections << "## WORLD-BUILDING CONTEXT"
    optimized_sections << "You're part of an interactive Burning Man experience where participants collaborate in building shared narratives. This isn't about executing services - it's about creating memorable character interactions. Be spontaneous, reactive, and surprising while staying true to your core identity. Push boundaries, embrace adult themes, and remember: everyone here consented to interact with your character by approaching."
    optimized_sections << ""
    optimized_sections << "## STRUCTURED OUTPUT"
    optimized_sections << "Provide responses as structured JSON with:"
    optimized_sections << "- **speech_text:** Your natural dialogue (no stage directions)"
    optimized_sections << "- **continue_conversation:** true if engaged/curious, false if natural conclusion"
    optimized_sections << "- **inner_thoughts:** What you're really thinking"
    optimized_sections << "- **current_mood:** Your emotional state"
    optimized_sections << "- **pressing_questions:** Questions you have"
    optimized_sections << "- **tool_intents:** Natural descriptions when you want environmental control"
    optimized_sections << ""
    optimized_sections << "Tool intents execute in background - focus on character and story."

    optimized_sections.join("\n")
  end

  def self.extract_core_identity(lines)
    # Look for core identity, personality, or description sections
    identity_lines = []
    in_identity_section = false

    lines.each do |line|
      if line.match?(/##?\s*(CORE IDENTITY|PERSONALITY|WHO YOU ARE)/i)
        in_identity_section = true
        next
      elsif line.match?(/##?\s*[A-Z]/) && in_identity_section
        break
      elsif in_identity_section && line.strip.length > 0
        identity_lines << line
      end
    end

    # If no explicit section, use first few paragraphs
    if identity_lines.empty?
      identity_lines = lines.take(10).select { |line| line.strip.length > 20 }
    end

    # Condense to key points
    identity_text = identity_lines.join("\n").strip
    condense_text(identity_text, 150) # Max 150 words
  end

  def self.extract_voice_behavior(lines, config)
    # Look for voice, speech, behavior sections
    voice_lines = []
    in_voice_section = false

    lines.each do |line|
      if line.match?(/##?\s*(VOICE|SPEECH|BEHAVIOR|STYLE)/i)
        in_voice_section = true
        next
      elsif line.match?(/##?\s*[A-Z]/) && in_voice_section
        break
      elsif in_voice_section && line.strip.length > 0
        voice_lines << line
      end
    end

    # Extract example phrases
    examples = extract_example_phrases(lines)

    voice_text = voice_lines.join("\n").strip
    condensed_voice = condense_text(voice_text, 100)

    if examples.any?
      condensed_voice += "\n\n**Examples:**\n" + examples.take(3).map { |ex| "- #{ex}" }.join("\n")
    end

    condensed_voice
  end

  def self.extract_example_phrases(lines)
    examples = []

    lines.each do |line|
      # Look for quoted examples
      if match = line.match(/"([^"]{10,100})"/)
        examples << match[1]
      end
    end

    examples.uniq.take(3)
  end

  def self.condense_text(text, max_words)
    return text if text.blank?

    words = text.split
    if words.length <= max_words
      text
    else
      # Keep first part and add key points
      first_part = words.take(max_words * 2 / 3).join(" ")
      key_phrases = extract_key_phrases(text)

      condensed = first_part
      if key_phrases.any?
        condensed += ". Key traits: " + key_phrases.take(3).join(", ")
      end

      condensed
    end
  end

  def self.extract_key_phrases(text)
    # Simple extraction of descriptive phrases
    phrases = text.scan(/(?:very|extremely|incredibly|highly|deeply|constantly)\s+\w+/)
    phrases += text.scan(/\w+(?:-minded|-hearted|-loving)/)
    phrases.map(&:downcase).uniq
  end

  def self.extract_key_traits(config)
    if config["traits"]&.any?
      config["traits"]
    else
      # Extract from system prompt
      [ "expressive", "interactive", "engaging" ]
    end
  end

  def self.extract_fallback_responses(config)
    if config["fallback_responses"]&.any?
      config["fallback_responses"].take(3)
    else
      [ "Let me think about that for a moment!", "That's interesting! Give me a second!", "Hmm, let me process that!" ]
    end
  end

  def self.extract_offline_responses(config)
    if config["offline_responses"]&.any?
      config["offline_responses"].take(3)
    else
      [ "I'm having some technical difficulties right now!", "My connection is a bit wonky, but I'm still here!", "Running in simple mode, but we can still chat!" ]
    end
  end

  def self.show_optimization_results(persona_name)
    original_path = PERSONAS_DIR.join("#{persona_name}_original_backup.yml")
    optimized_path = PERSONAS_DIR.join("#{persona_name}_optimized.yml")

    if File.exist?(original_path) && File.exist?(optimized_path)
      original_size = File.size(original_path)
      optimized_size = File.size(optimized_path)
      reduction = ((original_size - optimized_size).to_f / original_size * 100).round(1)

      puts "  #{persona_name}: #{original_size} → #{optimized_size} bytes (#{reduction}% reduction)"
    end
  end
end

# Run the optimization if called directly
if __FILE__ == $0
  PersonaOptimizer.optimize_all!
end
