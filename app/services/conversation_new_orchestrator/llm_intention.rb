# app/services/conversation_new_orchestrator/llm_intention.rb
class ConversationNewOrchestrator::LlmIntention
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
    ServiceResult.failure("LLM intention call failed: #{e.message}")
  end

  private

  def build_messages
    messages = []
    messages << { role: "system", content: @prompt_data[:system_prompt] } if @prompt_data[:system_prompt]
    messages.concat(@prompt_data[:messages]) if @prompt_data[:messages]&.any?
    messages << { role: "user", content: @user_message }
    messages
  end
end
