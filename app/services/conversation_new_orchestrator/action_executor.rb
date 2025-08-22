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
    direct_tool_results = execute_direct_tools
    memory_search_results = execute_memory_searches
    delegate_to_ha_agent

    all_sync_results = direct_tool_results.merge(memory_search_results)

    ServiceResult.success({
      sync_results: all_sync_results,
      delegated_intents: @output.dig("tool_intents") || []
    })
  rescue => e
    ServiceResult.failure("Action execution failed: #{e.message}")
  end

  private

  def execute_direct_tools
    direct_tool_calls = @output.dig("direct_tool_calls") || []
    return {} if direct_tool_calls.empty?

    results = {}
    direct_tool_calls.each do |tool_call|
      tool_name = tool_call["tool_name"]
      parameters = tool_call["parameters"] || {}

      begin
        # Convert string keys to symbols for Ruby method calls
        symbol_params = parameters.transform_keys(&:to_sym)

        # Execute the tool using the registry
        result = Tools::Registry.execute_tool(tool_name, **symbol_params)
        results[tool_name] = result

        Rails.logger.info "🔧 Direct tool executed: #{tool_name} - #{result[:success] ? 'SUCCESS' : 'FAILED'}"
      rescue => e
        Rails.logger.error "❌ Direct tool execution failed: #{tool_name} - #{e.message}"
        results[tool_name] = { success: false, error: e.message, tool: tool_name }
      end
    end

    results
  end

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

  def delegate_to_ha_agent
    intents = @output.dig("tool_intents")
    return if intents.blank?

    Rails.logger.info "🏠 Delegating #{intents.length} tool intentions to HA conversation agent"

    # Format intentions for HA agent
    intent_descriptions = intents.map do |intent|
      "#{intent['tool']}: #{intent['intent']}"
    end.join("; ")

    # Create a request that includes context
    ha_request = "User asked: \"#{@user_message}\". Please execute: #{intent_descriptions}"

    Rails.logger.info "🤖 Sending to HA agent: #{ha_request}"

    # Send to HA conversation agent asynchronously
    HaAgentJob.perform_later(
      request: ha_request,
      tool_intents: intents,
      session_id: @session_id,
      conversation_id: @conversation_id,
      user_message: @user_message
    )
  end
end
