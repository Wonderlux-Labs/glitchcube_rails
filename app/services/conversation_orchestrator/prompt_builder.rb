# app/services/conversation_orchestrator/prompt_builder.rb
class ConversationOrchestrator::PromptBuilder
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

    # Check for and inject any pending HA results from a previous turn
    inject_previous_ha_results(prompt_data)
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
    instruction = result["instruction"].presence || "an environment change"

    if result["error"]
      "System note: You tried to '#{instruction}' but it failed: #{result['error']}"
    else
      # ha_response is the Home Assistant agent's natural-language reply,
      # captured by EnvironmentDirectorJob.
      "System note: You intended to '#{instruction}'. Result: #{result['ha_response']}"
    end
  end
end
