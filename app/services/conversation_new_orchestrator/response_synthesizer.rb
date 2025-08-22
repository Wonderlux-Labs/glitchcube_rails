# app/services/conversation_new_orchestrator/response_synthesizer.rb
class ConversationNewOrchestrator::ResponseSynthesizer
  def self.call(llm_response:, action_results:, prompt_data:)
    new(llm_response: llm_response, action_results: action_results, prompt_data: prompt_data).call
  end

  def initialize(llm_response:, action_results:, prompt_data:)
    @llm_response = llm_response
    @action_results = action_results
    @prompt_data = prompt_data
  end

  def call
    ai_response = generate_final_response
    ServiceResult.success(ai_response)
  rescue => e
    ServiceResult.failure("Response synthesis failed: #{e.message}")
  end

  private

  def generate_final_response
    response_id = SecureRandom.uuid

    # Extract narrative elements from structured output
    structured_data = @llm_response.deep_stringify_keys
    speech_text = structured_data["speech_text"]
    continue_conversation = structured_data["continue_conversation"] || false

    # Extract narrative metadata if available
    narrative = {
      continue_conversation: continue_conversation,
      inner_thoughts: structured_data["inner_thoughts"],
      current_mood: structured_data["current_mood"],
      pressing_questions: structured_data["pressing_questions"],
      goal_progress: structured_data["goal_progress"],
      speech_text: speech_text
    }

    # Handle empty speech case
    if speech_text.blank?
      speech_text = "I understand."
    end

    # SPEECH AMENDMENT: If we have query tool results, call LLM again to amend speech
    query_results = filter_query_tool_results(@action_results[:sync_results] || {})
    if query_results.any?
      speech_text = amend_speech_with_query_results(speech_text, query_results, @prompt_data)
    end

    # Fallback for completely empty speech
    if speech_text.blank?
      speech_text = "I understand."
    end

    {
      id: response_id,
      text: speech_text,
      continue_conversation: narrative[:continue_conversation],
      inner_thoughts: narrative[:inner_thoughts],
      current_mood: narrative[:current_mood],
      pressing_questions: narrative[:pressing_questions],
      goal_progress: narrative[:goal_progress],
      success: true,
      speech_text: speech_text  # Also include as :speech_text for compatibility
    }
  end

  def filter_query_tool_results(sync_results)
    query_results = {}

    sync_results.each do |tool_name, result|
      # Only include results from query tools
      if Tools::Registry.tool_intent(tool_name) == :query && result
        query_results[tool_name] = result
      end
    end

    query_results
  end

  def amend_speech_with_query_results(original_speech, query_results, prompt_data)
    # Build query results summary with safe key access
    results_summary = query_results.map do |tool_name, result|
      success = result["success"] || result[:success]
      if success
        message = result["message"] || result[:message] || result["data"] || result[:data] || "completed"
        "#{tool_name}: #{message}"
      else
        error = result["error"] || result[:error] || "failed"
        "#{tool_name}: #{error}"
      end
    end.join(", ")

    # Call LLM to amend the speech naturally
    # Sanitize inputs to prevent injection attacks
    sanitized_speech = original_speech.to_s.gsub(/["\n\r]/, ' ').truncate(Rails.configuration.llm_input_max_speech_length)
    sanitized_results = results_summary.to_s.gsub(/["\n\r]/, ' ').truncate(Rails.configuration.llm_input_max_results_length)
    
    amendment_messages = [
      { role: "system", content: prompt_data[:system_prompt] },
      {
        role: "user",
        content: "Please amend this response to naturally include the tool results: \"#{sanitized_speech}\"\n\nTool results: #{sanitized_results}\n\nReturn only the amended speech, staying in character."
      }
    ]

    begin
      # Add timeout protection to prevent resource exhaustion
      amendment_response = Timeout::timeout(Rails.configuration.llm_amendment_timeout) do
        LlmService.call_with_tools(
          messages: amendment_messages,
          tools: [], # No tools for amendment call
          model: Rails.configuration.default_ai_model
        )
      end

      amended_speech = amendment_response.content&.strip
      return amended_speech if amended_speech.present?
    rescue => e
      Rails.logger.warn "Failed to amend speech: #{e.message}"
    end

    # Fallback: return original speech if amendment fails
    original_speech
  end
end
