# app/services/conversation_new_orchestrator/action_executor.rb
class ConversationNewOrchestrator::ActionExecutor
  def self.call(llm_response:, session_id:, conversation_id:, user_message:)
    new(llm_response: llm_response, session_id: session_id, conversation_id: conversation_id, user_message: user_message).call
  end

  def initialize(llm_response:, session_id:, conversation_id:, user_message:)
    @output = llm_response || {}
    @session_id = session_id
    @conversation_id = conversation_id
    @user_message = user_message
  end

  def call
    memory_search_results = execute_memory_searches
    dispatched = dispatch_environment_instruction

    ServiceResult.success({
      sync_results: memory_search_results,
      dispatched_environment: dispatched
    })
  rescue => e
    ServiceResult.failure("Action execution failed: #{e.message}")
  end

  private

  def execute_memory_searches
    memory_searches = @output.dig("search_memories") || []
    return {} if memory_searches.empty?

    results = {}
    memory_searches.each_with_index do |search_request, index|
      query = search_request["query"]
      type = search_request["type"] || "all"
      limit = Rails.configuration.memory_search_limit

      begin
        search_result = Tools::Registry.execute_tool(
          "rag_search",
          query: query,
          type: type,
          limit: limit
        )

        search_key = "memory_search_#{index + 1}"
        results[search_key] = search_result

        Rails.logger.info "🧠 Memory search executed: #{query} (#{type}) - found #{search_result[:total_results] || 0} results"
      rescue => e
        Rails.logger.error "❌ Memory search failed: #{query} - #{e.message}"
        search_key = "memory_search_#{index + 1}"
        results[search_key] = { success: false, error: e.message, query: query }
      end
    end

    results
  end

  # The brain LLM describes every environment change as one plain-English
  # `environment_instruction` ("turn the lights orange and play heavy metal").
  def environment_instruction
    @output.dig("environment_instruction").presence
  end

  # Replaces the old per-domain fan-out to Home Assistant conversation agents.
  # All environment changes go through one translator (ToolCallingService) via
  # EnvironmentDirectorJob — speak first, act async. Returns true if dispatched.
  def dispatch_environment_instruction
    instruction = environment_instruction
    return false if instruction.blank?

    Rails.logger.info "🎬 Dispatching environment instruction: #{instruction}"

    EnvironmentDirectorJob.perform_later(
      instruction: instruction,
      session_id: @session_id,
      conversation_id: @conversation_id,
      user_message: @user_message,
      persona: @output.dig("persona")
    )
    true
  end
end
