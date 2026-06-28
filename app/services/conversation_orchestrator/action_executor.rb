# app/services/conversation_orchestrator/action_executor.rb
class ConversationOrchestrator::ActionExecutor
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

    # Enqueue async so embedding calls never block the spoken response.
    # Results land in conversation.metadata_json["pending_query_results"]
    # and are injected into the next turn's context.
    MemorySearchJob.perform_later(
      conversation_id: @conversation_id,
      searches: memory_searches
    )
    Rails.logger.info "🔍 Enqueued #{memory_searches.size} memory search(es) async"
    {}
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
