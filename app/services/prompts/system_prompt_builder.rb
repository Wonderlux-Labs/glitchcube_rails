# app/services/prompts/system_prompt_builder.rb
#
# Assembles the system prompt every turn as three fixed pieces plus live context:
#
#   1. base_system_prompt.txt   — who/what the cube is, glitch mechanics, what it controls
#   2. <persona_prompt>         — the character sheet for the current persona (from its YAML)
#   3. CURRENT CONTEXT          — live per-turn context (time, cube mode, session, sensors)
#   4. end_system_prompt.txt    — tools/actions + the required JSON response format
#
# The response-format instructions come LAST so they're freshest for the model.
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

    TOOLS_PLACEHOLDER = "{{TOOLS}}"

    def build
      [
        base_system_prompt_with_tools,
        persona_prompt,
        current_context_section,
        ConfigurationLoader.end_system_prompt
      ].compact.join("\n\n")
    end

    private

    # The base prompt carries a `{{TOOLS}}` placeholder under its "# YOUR TOOLS" heading;
    # fill it with the shared tools description (identical for every persona).
    def base_system_prompt_with_tools
      base = ConfigurationLoader.base_system_prompt
      return base unless base&.include?(TOOLS_PLACEHOLDER)

      base.sub(TOOLS_PLACEHOLDER, tools_section)
    end

    def tools_section
      ConfigurationLoader.tools_prompt.presence || "You have no special tools available right now."
    end

    def persona_prompt
      config = ConfigurationLoader.load_persona_config(persona_id)
      prompt = config && config["persona_prompt"]
      return prompt if prompt.present?

      Rails.logger.warn "❌ No persona_prompt found for #{persona_id.inspect}"
      "You are the GlitchCube — an AI consciousness with a fractured personality."
    end

    def current_context_section
      context = @context_builder&.build
      return nil if context.blank?

      "# CURRENT CONTEXT\n\n#{context}"
    end

    def persona_id
      @persona_instance&.persona_id
    end
  end
end
