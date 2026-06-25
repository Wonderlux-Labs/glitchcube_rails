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

      # Build basic context
      basic_context = @context_builder ? @context_builder.build : "Cube installation active"

      # Enhance with RAG and system-specific context
      enhanced_context = SystemContextEnhancer.enhance(
        basic_context,
        user_message: @user_message
      )

      enhanced_parts = [
        base_prompt,
        "",
        base_system_rules,
        "",
        "CURRENT CONTEXT:",
        enhanced_context
      ]

      enhanced_parts.join("\n")
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

      # Goal integration
      if config["goal_integration"]
        goal_rules = config["goal_integration"]["rules"]
        current_goal = get_current_goal_description
        goal_rules_with_goal = goal_rules.gsub("{{GOAL_PLACEHOLDER}}", current_goal)

        parts << config["goal_integration"]["description"]
        parts << goal_rules_with_goal
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

    def get_current_goal_description
      begin
        goal_status = GoalService.current_goal_status
        goal_status&.dig(:goal_description) || "Explore this interaction and create memorable moments"
      rescue StandardError => e
        Rails.logger.warn "Failed to get current goal: #{e.message}"
        "Be spontaneous and create engaging interactions"
      end
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
