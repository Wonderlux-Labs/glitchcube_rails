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

    # A failed/timed-out call comes back with a non-blank apology in `content` but
    # NO structured_output. The brain pipeline needs the structured hash, so treat a
    # blank structured_output as a failure and fall through to fallback_narrative —
    # otherwise we'd pass nil forward and crash response synthesis.
    raise "LLM returned no structured output" if response.structured_output.blank?

    ConversationLogger.llm_response(response.model || @model, response.content, [], { usage: response.usage })

    # Smoke test: the brain may surface `ooc_questions` — out-of-character questions
    # for a director/programmer about its character or the project. Nothing is wired
    # to answer them yet; we only LOG them so we can see whether personas ask anything
    # worth folding into steering later. See docs/conversation_flow.md.
    log_ooc_questions(response.structured_output["ooc_questions"])

    ServiceResult.success({ llm_response: response.structured_output, usage: usage_for(response) })
  rescue => e
    ConversationLogger.error("LLM Intention", e.message, { model: @model, user_message: @user_message })
    # The brain LLM is the ONE place we degrade gracefully instead of failing
    # loudly (see CLAUDE.md): if OpenRouter errors, the cube must still speak
    # rather than go silent or surface a stack-trace error. Return a synthetic
    # narrative so the rest of the pipeline finishes normally and the turn is
    # persisted. Validation failures above still fail loudly — those are bugs.
    ServiceResult.success({ llm_response: fallback_narrative, usage: nil })
  end

  private

  # Tag on which model actually answered (a timeout can fall back to a
  # different model than requested) so the admin conversation log can show it.
  def usage_for(response)
    u = response.usage
    return nil if u.blank?

    {
      "model" => response.model || @model,
      "prompt_tokens" => u["prompt_tokens"],
      "completion_tokens" => u["completion_tokens"],
      "total_tokens" => u["total_tokens"],
      "cost" => u["cost"]
    }
  end

  def log_ooc_questions(questions)
    return if questions.blank?

    # Distinctive tag so we can grep what personas actually want to ask.
    Rails.logger.info "🎬 [ooc_questions] (collected only, nothing wired to answer): #{questions}"
  end

  def fallback_narrative
    {
      "speech" => "I'm having trouble thinking right now — give me a moment.",
      "continue_conversation" => false,
      "inner_monologue" => "Brain LLM call failed; spoke a graceful fallback so I'm not silent.",
      "actions" => []
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
