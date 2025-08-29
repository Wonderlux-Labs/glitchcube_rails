# app/services/prompt_service.rb
require "digest"

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
    @context_builder = Prompts::ContextBuilder.new(
      conversation: @conversation,
      extra_context: @extra_context,
      user_message: @user_message
    )
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
    # Use cached system prompt if available for this conversation
    if @conversation && cached_system_prompt.present?
      Rails.logger.debug "🚀 Using cached system prompt for conversation #{@conversation.session_id}"
      return cached_system_prompt
    end

    # Build new system prompt
    system_prompt = Prompts::SystemPromptBuilder.build(
      persona_instance: @persona_instance,
      context_builder: @context_builder,
      user_message: @user_message
    )

    # Cache it for this conversation
    cache_system_prompt(system_prompt) if @conversation

    system_prompt
  end

  def build_message_history
    Prompts::MessageHistoryBuilder.build(@conversation)
  end

  def build_tools_for_persona
    Rails.logger.info "🎭 Optimized prompt mode - no tool definitions needed (using tool_intents)"
    []
  end

  def cached_system_prompt
    return nil unless @conversation&.metadata_json

    cache_key = generate_cache_key
    cached_data = @conversation.metadata_json["cached_system_prompt"]

    return nil unless cached_data
    return nil unless cached_data["cache_key"] == cache_key

    cached_data["system_prompt"]
  end

  def cache_system_prompt(system_prompt)
    return unless @conversation

    cache_key = generate_cache_key
    metadata = @conversation.metadata_json.dup

    metadata["cached_system_prompt"] = {
      "system_prompt" => system_prompt,
      "cache_key" => cache_key,
      "cached_at" => Time.current.iso8601
    }

    @conversation.update!(metadata_json: metadata)
    Rails.logger.debug "💾 Cached system prompt for conversation #{@conversation.session_id}"
  end

  def generate_cache_key
    # Cache key includes factors that would invalidate the system prompt
    components = [
      @persona_name,
      Date.current.to_s, # New day = new cache (for time-sensitive context)
      @conversation&.persona # In case persona changes mid-conversation
    ]

    Digest::SHA256.hexdigest(components.compact.join("|"))[0..12]
  end
end
