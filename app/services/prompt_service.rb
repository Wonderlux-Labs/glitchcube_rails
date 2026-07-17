# app/services/prompt_service.rb
class PromptService
  def self.build_prompt_for(persona: nil, conversation:, extra_context: {}, user_message: nil)
    new(
      persona: persona,
      conversation: conversation,
      extra_context: extra_context,
      user_message: user_message
    ).build
  end

  def initialize(persona:, conversation:, extra_context:, user_message: nil)
    @persona_name = persona || CubePersona.current_persona
    @conversation = conversation
    @extra_context = extra_context
    @user_message = user_message

    @persona_instance = Prompts::PersonaLoader.load(@persona_name)
    @context_builder = Prompts::ContextBuilder.new(persona: @persona_name, conversation: @conversation)
  end

  def build
    {
      system_prompt: build_system_prompt,
      messages: build_message_history,
      tools: build_tools_for_persona,
      context: @context_builder.build
    }
  end

  private

  def build_system_prompt
    # Rebuilt fresh every turn — the self-model (character sheet, live capabilities,
    # recent memories) is state-dependent and cheap to assemble (no LLM), so there
    # is nothing to cache. A same-turn capability unlock must be visible immediately.
    Prompts::SystemPromptBuilder.build(
      persona_instance: @persona_instance,
      context_builder: @context_builder,
      user_message: @user_message
    )
  end

  def build_message_history
    Prompts::MessageHistoryBuilder.build(@conversation)
  end

  def build_tools_for_persona
    # The brain LLM never receives tool definitions — it emits a plain-English
    # environment_instruction that the translator turns into tool calls.
    []
  end
end
