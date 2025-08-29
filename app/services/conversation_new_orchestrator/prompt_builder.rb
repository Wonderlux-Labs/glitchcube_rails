# app/services/conversation_new_orchestrator/prompt_builder.rb
class ConversationNewOrchestrator::PromptBuilder
  def self.call(conversation:, persona:, user_message:, context:)
    new(conversation: conversation, persona: persona, user_message: user_message, context: context).call
  end

  def initialize(conversation:, persona:, user_message:, context:)
    @conversation = conversation
    @persona = persona
    @user_message = user_message
    @context = context
  end

  def call
    # Build base prompt using existing PromptService
    prompt_data = PromptService.build_prompt_for(
      persona: @persona,
      conversation: @conversation,
      extra_context: @context,
      user_message: @user_message
    )

    # Check for and inject any pending results from a previous turn
    inject_previous_ha_results(prompt_data)
    inject_previous_query_results(prompt_data)
    Rails.logger.debug("Prompt built: messages=#{prompt_data[:messages].size}, has_system=#{prompt_data[:system_prompt].present?}")
    ServiceResult.success(prompt_data)
  rescue => e
    ServiceResult.failure("Prompt building failed: #{e.message}")
  end

  private

  def inject_previous_ha_results(prompt_data)
    unprocessed_results = check_and_clear_ha_results
    return if unprocessed_results.empty?

    Rails.logger.info "🏠 Injecting #{unprocessed_results.length} HA results into conversation"

    unprocessed_results.each do |result|
      result_text = format_ha_result_for_llm(result)
      system_msg = { role: "system", content: result_text }
      # Append to end of message history
      prompt_data[:messages] << system_msg
      Rails.logger.info "🔄 Injected: #{result_text}"
    end
  end

  def check_and_clear_ha_results
    return [] unless @conversation.metadata_json

    pending_results = @conversation.metadata_json["pending_ha_results"] || []
    unprocessed_results = pending_results.reject { |r| r["processed"] }

    return [] if unprocessed_results.empty?

    Rails.logger.info "🏠 Found #{unprocessed_results.length} unprocessed HA results"

    # Mark all as processed
    updated_results = pending_results.map do |result|
      result["processed"] = true if !result["processed"]
      result
    end

    # Update conversation metadata
    updated_metadata = @conversation.metadata_json.merge(
      "pending_ha_results" => updated_results
    )
    @conversation.update!(metadata_json: updated_metadata)

    # Return results for injection
    unprocessed_results
  end

  def format_ha_result_for_llm(result)
    if result["error"]
      "System note: You tried to execute '#{format_tool_intents(result['tool_intents'])}' but it failed: #{result['error']}"
    else
      success_items = result.dig("ha_response", "response", "data", "success") || []
      failed_items = result.dig("ha_response", "response", "data", "failed") || []

      success_summary = success_items.map { |item| item["name"] || item["entity_id"] }.join(", ")
      failed_summary = failed_items.map { |item| "#{item['name'] || item['entity_id']} (#{item['error']})" }.join(", ")

      parts = []
      parts << "#{success_summary} completed" if success_summary.present?
      parts << "#{failed_summary} failed" if failed_summary.present?

      "System note: You intended to #{format_tool_intents(result['tool_intents'])}. Result: #{parts.join(', ')}"
    end
  end

  def format_tool_intents(tool_intents)
    return "unknown action" unless tool_intents.is_a?(Array)
    tool_intents.map { |intent| "#{intent['intent']}" }.join(" and ")
  end

  def inject_previous_query_results(prompt_data)
    return unless @conversation.metadata_json

    query_results = @conversation.metadata_json["pending_query_results"]
    return unless query_results && query_results["results_summary"]

    Rails.logger.info "🔍 Injecting query results from previous turn: #{query_results['tool_count']} tools"

    # Create a system message with the query results
    result_text = "System note: Previous query results from your last response: #{query_results['results_summary']}"
    system_msg = { role: "system", content: result_text }

    # Append to end of message history
    prompt_data[:messages] << system_msg
    Rails.logger.info "🔄 Injected query results: #{result_text}"

    # Clear the pending query results now that we've injected them
    clear_query_results
  end

  def clear_query_results
    return unless @conversation.metadata_json

    metadata = @conversation.metadata_json.dup
    metadata.delete("pending_query_results")

    begin
      @conversation.update!(metadata_json: metadata)
    rescue => e
      Rails.logger.warn "Failed to clear query results: #{e.message}"
    end
  end
end
