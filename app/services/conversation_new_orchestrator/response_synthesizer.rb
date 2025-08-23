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

    # DEFERRED QUERY RESULTS: Store query tool results for next conversation turn
    # This prevents blocking TTS with synchronous LLM calls
    query_results = filter_query_tool_results(@action_results[:sync_results] || {})
    if query_results.any?
      store_query_results_for_next_turn(query_results)
      Rails.logger.info "🔄 Stored #{query_results.keys.count} query results for next conversation turn"
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

  def store_query_results_for_next_turn(query_results)
    # Store query results in conversation metadata for the next turn
    # This way the LLM gets the context without blocking current response
    return unless @prompt_data[:conversation]

    # Build a summary of the query results
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

    # Store in conversation metadata for next turn injection
    conversation = @prompt_data[:conversation]
    metadata = conversation.metadata_json || {}
    metadata["pending_query_results"] = {
      timestamp: Time.current.iso8601,
      results_summary: results_summary,
      tool_count: query_results.keys.count
    }

    begin
      conversation.update!(metadata_json: metadata)
    rescue => e
      Rails.logger.warn "Failed to store query results for next turn: #{e.message}"
    end
  end

  # REMOVED: amend_speech_with_query_results method
  # Query results are now stored for the next conversation turn instead of
  # blocking the current response with synchronous LLM calls
end
