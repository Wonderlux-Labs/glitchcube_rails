# app/services/tool_calling_service.rb
#
# Translator LLM. Receives a single plain-English instruction from the brain (one
# action channel, e.g. "lights: bright magenta and slow breathing") plus a lane
# (:action / :sound), and translates it into precise, validated Home Assistant tool
# calls, retrying on validation errors, then executes them. Runs at low temperature.
#
# It always returns ONE normalized struct so the caller (EnvironmentDirectorJob) can
# fold a rich, honest record of what happened into the next turn:
#
#   {
#     success:       true/false,
#     narrative:     "human-readable summary" (folded into the brain's next prompt),
#     tool_calls:    [{ name:, arguments: }, ...]  (what the translator decided),
#     service_calls: [{ domain:, service:, data: }, ...]  (what actually fired at HASS),
#     error:         nil or a string
#   }
class ToolCallingService
  def initialize(session_id: nil, conversation_id: nil)
    @session_id = session_id
    @conversation_id = conversation_id
    @max_iterations = Rails.configuration.try(:tool_calling_max_iterations) || 5
  end

  def execute_intent(intent, context = {})
    lane = (context[:lane] || :action).to_sym
    Rails.logger.info "🔧 ToolCallingService [#{lane}] executing intent: #{intent}"

    definitions = Tools::Registry.tool_definitions_for_lane(lane)
    current_intent = intent
    iteration = 1

    while iteration <= @max_iterations
      response = call_translator_llm(current_intent, context, lane, definitions)
      return failure_result("translator returned no response") unless response

      calls = Array(response.tool_calls)
      return no_action_result(response) if calls.empty?

      validated = calls.map { |tc| ValidatedToolCall.new(tc, Tools::Registry.definition_for(tc.name)) }
      invalid = validated.reject(&:valid?)

      if invalid.any? && iteration < @max_iterations
        Rails.logger.warn "⚠️ [#{lane}] validation errors on attempt #{iteration}, retrying with feedback"
        current_intent = build_retry_intent(intent, invalid)
        iteration += 1
        next
      end

      return execute_and_summarize(validated, invalid)
    end

    failure_result("exhausted retries without a valid tool call")
  end

  private

  def call_translator_llm(intent, context, lane, definitions)
    LlmService.call_with_tools(
      messages: build_messages(intent, context),
      tools: definitions,
      model: Rails.configuration.hass_tool_calling_model,
      temperature: 0.1 # precise, deterministic technical execution
    )
  end

  def build_messages(intent, context)
    [
      {
        role: "system",
        content: <<~SYSTEM
          You are the cube's technical tool-execution service. Translate the natural-language
          instruction into precise tool calls using ONLY the tools provided.

          - Use EXACT parameter names and value formats from the tool definitions.
          - Make the tool call(s) needed to fulfill the instruction — reason and make a sensible
            choice when it isn't spelled out.
          - If a call fails validation you'll be told why; fix it and try again.
          - If the instruction needs no action, make no tool call.

          CONTEXT: #{context.except(:lane).to_json}
        SYSTEM
      },
      { role: "user", content: intent.to_s }
    ]
  end

  # Execute the valid calls; collect what fired and any errors into the normalized struct.
  def execute_and_summarize(validated, invalid)
    executed = []
    service_calls = []
    errors = invalid.map { |v| "#{v.name}: #{v.validation_errors.join('; ')}" }

    validated.select(&:valid?).each do |call|
      result = Tools::Registry.execute_tool(call.name, **call.arguments)
      executed << { name: call.name, arguments: call.arguments }

      if HashUtils.get(result, "success")
        Array(HashUtils.get(result, "service_calls")).each { |sc| service_calls << sc }
      else
        errors << "#{call.name}: #{HashUtils.get(result, 'error')}"
      end
    rescue StandardError => e
      Rails.logger.error "❌ Tool #{call.name} raised: #{e.message}"
      errors << "#{call.name}: #{e.message}"
    end

    success = errors.empty? && executed.any?
    {
      success: success,
      narrative: summarize(executed, errors),
      tool_calls: executed,
      service_calls: service_calls,
      error: errors.presence&.join(". ")
    }
  end

  def summarize(executed, errors)
    parts = []
    parts << "Did: #{executed.map { |c| humanize(c[:name]) }.join(', ')}" if executed.any?
    parts << "Failed: #{errors.join('; ')}" if errors.any?
    parts.presence&.join(" — ") || "Nothing to do."
  end

  def humanize(tool_name)
    tool_name.to_s.tr("_", " ")
  end

  def build_retry_intent(original_intent, invalid)
    feedback = invalid.map { |v| "#{v.name}: #{v.validation_errors.join('; ')}" }.join(". ")
    "#{original_intent}\n\nCORRECTIONS NEEDED: #{feedback}. Fix these and try again."
  end

  def no_action_result(response)
    {
      success: true,
      narrative: response.respond_to?(:content) && response.content.present? ? response.content : "Nothing to do.",
      tool_calls: [],
      service_calls: [],
      error: nil
    }
  end

  def failure_result(message)
    { success: false, narrative: message, tool_calls: [], service_calls: [], error: message }
  end
end
