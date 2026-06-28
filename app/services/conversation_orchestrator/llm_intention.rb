# app/services/conversation_orchestrator/llm_intention.rb
class ConversationOrchestrator::LlmIntention
  def self.call(prompt_data:, user_message:, model:)
    new(prompt_data: prompt_data, user_message: user_message, model: model).call
  end

  def initialize(prompt_data:, user_message:, model:)
    @prompt_data = prompt_data
    @user_message = user_message
    @model = model
  end

  def call
    return ServiceResult.failure("LLM intention call failed: prompt_data is required") if @prompt_data.nil?
    if @user_message.nil?
      return ServiceResult.failure("LLM intention call failed: user_message is required")
    elsif @user_message.blank?
      return ServiceResult.failure("LLM intention call failed: user_message cannot be empty")
    end

    if @model.nil?
      return ServiceResult.failure("LLM intention call failed: model is required")
    elsif @model.blank?
      return ServiceResult.failure("LLM intention call failed: model cannot be empty")
    end

    # Validate prompt_data structure
    unless @prompt_data.is_a?(Hash) && @prompt_data[:messages].is_a?(Array)
      return ServiceResult.failure("LLM intention call failed: prompt_data must contain messages")
    end

    messages = build_messages
    schema = Schemas::NarrativeResponseSchema.schema

    ConversationLogger.llm_request(@model, @user_message, schema)

    response = LlmService.call_with_structured_output(
      messages: messages,
      response_format: schema,
      model: @model
    )

    raise "LLM response was empty" if response.content.blank? && response.structured_output.blank?

    ConversationLogger.llm_response(response.model || @model, response.content, [], { usage: response.usage })

    ServiceResult.success({ llm_response: response.structured_output })
  rescue => e
    ConversationLogger.error("LLM Intention", e.message, { model: @model, user_message: @user_message })
    # The brain LLM is the ONE place we degrade gracefully instead of failing
    # loudly (see CLAUDE.md): if OpenRouter errors, the cube must still speak
    # rather than go silent or surface a stack-trace error. Return a synthetic
    # narrative so the rest of the pipeline finishes normally and the turn is
    # persisted. Validation failures above still fail loudly — those are bugs.
    ServiceResult.success({ llm_response: fallback_narrative })
  end

  private

  def fallback_narrative
    {
      "speech_text" => "I'm having trouble thinking right now — give me a moment.",
      "continue_conversation" => false,
      "inner_thoughts" => "Brain LLM call failed; spoke a graceful fallback so I'm not silent.",
      "environment_instruction" => "",
      "search_memories" => []
    }
  end

  def build_messages
    messages = []

    # CRITICAL: System message MUST be first - never after conversation history!
    if @prompt_data[:system_prompt].present?
      messages << { role: "system", content: @prompt_data[:system_prompt] }
      Rails.logger.debug "📋 System prompt added FIRST (#{@prompt_data[:system_prompt].length} chars)"
    end

    # Add conversation history AFTER system message
    if @prompt_data[:messages]&.any?
      messages.concat(@prompt_data[:messages])
      Rails.logger.debug "💬 Added #{@prompt_data[:messages].length} history messages"
    end

    # Add current user message last
    messages << { role: "user", content: @user_message }

    # Verify system message is first
    if messages.first&.dig(:role) != "system"
      Rails.logger.error "🚨 CRITICAL: System message is not first! Order: #{messages.map { |m| m[:role] }.join(' → ')}"
    else
      Rails.logger.debug "✅ Message order correct: #{messages.map { |m| m[:role] }.join(' → ')}"
    end

    messages
  end
end
