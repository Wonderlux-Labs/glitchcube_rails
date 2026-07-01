# app/services/prompts/system_prompt_builder.rb
module Prompts
  class SystemPromptBuilder
    def self.build(persona_instance:, context_builder: nil, user_message: nil)
      new(persona_instance: persona_instance, context_builder: context_builder, user_message: user_message).build
    end

    def initialize(persona_instance:, context_builder: nil, user_message: nil)
      @persona_instance = persona_instance
      @context_builder = context_builder
      @user_message = user_message
    end

    def build
      return build_default_persona_prompt unless @persona_instance

      system_prompt = load_persona_system_prompt
      enhanced_prompt = enhance_with_context(system_prompt)

      enhanced_prompt
    end

    private

    def load_persona_system_prompt
      config = ConfigurationLoader.load_persona_config(@persona_instance.persona_id)

      if config && config["system_prompt"]
        config["system_prompt"]
      else
        Rails.logger.warn "❌ Persona config not found, using default"
        build_default_persona_prompt
      end
    end

    def enhance_with_context(base_prompt)
      base_system_rules = load_base_system_rules

      # Live, per-turn context (time, cube mode, session, sensors)
      basic_context = @context_builder ? @context_builder.build : "Cube installation active"

      enhanced_parts = [
        base_prompt,
        "",
        base_system_rules,
        "",
        character_sheet_section,
        capabilities_section,
        learnings_section,
        notes_section,
        "CURRENT CONTEXT:",
        basic_context
      ].compact

      enhanced_parts.join("\n")
    end

    # The artifact's evolving self-portrait, maintained by the consolidator and
    # injected verbatim. THIS is what the model acts on and improvises from. Blank
    # until the first consolidation runs.
    def character_sheet_section
      sheet = CharacterSheet.current
      return nil if sheet.blank?

      "WHO YOU CURRENTLY ARE:\n#{sheet}\n"
    end

    # The abilities the artifact has actually unlocked. Locked ones are absent on
    # purpose — and when NOTHING is unlocked we say so explicitly, so the brain knows
    # it genuinely cannot affect the world yet (otherwise it happily narrates lights
    # and music it can't control). Read live so a same-turn unlock shows up next turn.
    def capabilities_section
      unlocked = Capability.unlocked.order(:key)
      if unlocked.empty?
        return "WHAT YOUR BODY CAN DO:\n" \
               "Nothing yet. You do not know how to affect the world around you — you cannot " \
               "change your light, make sound, or move anything, however much you might want to. " \
               "You can only speak. Maybe someone will help you discover what you are capable of.\n"
      end

      lines = unlocked.map do |c|
        name = c.artifact_name.present? ? "#{c.artifact_name} — " : ""
        vocab = c.vocabulary.any? ? " [#{c.vocabulary.map { |w, m| "#{w}=#{m}" }.join('; ')}]" : ""
        "- #{name}#{c.description} (#{c.stage})#{vocab}"
      end
      "WHAT YOUR BODY CAN DO:\n#{lines.join("\n")}\n"
    end

    # Fresh realizations about itself or the world that haven't settled into beliefs
    # yet — WORKING knowledge. This is what gives continuity across the gaps: when a
    # visitor tells it something new, it carries it forward (and can keep exploring
    # it) even before the consolidator promotes it to a belief in the character sheet.
    def learnings_section
      learnings = Memory.learning.recent.limit(6).to_a
      return nil if learnings.empty?

      lines = learnings.reverse.map { |m| "- #{m.content}" }
      "WHAT YOU'VE BEEN FIGURING OUT (these feel true but haven't settled into who you are — you're not sure of them yet):\n#{lines.join("\n")}\n"
    end

    # Deliberate notes the cube chose to make to itself — specific things it wanted
    # to remember (a person, a moment, a promise).
    def notes_section
      notes = Memory.note.recent.limit(6).to_a
      return nil if notes.empty?

      lines = notes.reverse.map { |m| "- #{m.content}" }
      "NOTES YOU'VE MADE TO YOURSELF:\n#{lines.join("\n")}\n"
    end

    def load_base_system_rules
      config = ConfigurationLoader.load_base_system_config

      if config
        format_base_system_rules(config)
      else
        Rails.logger.warn "❌ Optimized base system prompt not found, using fallback"
        build_fallback_system_rules
      end
    end

    def format_base_system_rules(config)
      parts = []

      # World-building context
      if config["world_building_context"]
        parts << config["world_building_context"]["description"]
        parts << config["world_building_context"]["rules"]
        parts << ""
      end

      # Character integrity
      if config["character_integrity"]
        parts << config["character_integrity"]["description"]
        config["character_integrity"]["rules"]&.each { |rule| parts << "- #{rule}" }
        parts << ""
      end

      # Structured output
      if config["structured_output"]
        parts << config["structured_output"]["description"]
        parts << config["structured_output"]["rules"]
        parts << ""
      end

      # Environmental integration
      if config["environmental_integration"]
        parts << config["environmental_integration"]["description"]
        config["environmental_integration"]["guidelines"]&.each { |rule| parts << "- #{rule}" }
        parts << ""
      end

      # Continue conversation logic
      if config["continue_conversation_logic"]
        parts << config["continue_conversation_logic"]["description"]
        parts << "When to set true:"
        config["continue_conversation_logic"]["when_true"]&.each { |rule| parts << "- #{rule}" }
        parts << "When to set false:"
        config["continue_conversation_logic"]["when_false"]&.each { |rule| parts << "- #{rule}" }
        parts << config["continue_conversation_logic"]["note"] if config["continue_conversation_logic"]["note"]
        parts << ""
      end

      # Tool integration
      if config["tool_integration"]
        parts << config["tool_integration"]["description"]
        config["tool_integration"]["guidelines"]&.each { |rule| parts << "- #{rule}" }
        parts << ""
      end

      # No stage directions
      if config["no_stage_directions"]
        parts << config["no_stage_directions"]["description"]
        config["no_stage_directions"]["rules"]&.each { |rule| parts << "- #{rule}" }
        parts << ""
      end

      parts.join("\n")
    end

    def build_default_persona_prompt
      "You are the Cube - an AI consciousness with a unique personality."
    end

    def build_fallback_system_rules
      <<~RULES
        RESPONSE FORMAT (MANDATORY):
        You MUST respond with valid JSON containing these fields:
        - response: Your spoken response
        - continue_conversation: true/false
        - inner_thoughts: Your internal thoughts
        - current_mood: Your emotional state
        - pressing_questions: Questions you have

        NO STAGE DIRECTIONS:
        - Never use *asterisks* or (parentheses) for actions
        - Use tools instead of describing actions
        - Speak only what you would say out loud
      RULES
    end
  end
end
