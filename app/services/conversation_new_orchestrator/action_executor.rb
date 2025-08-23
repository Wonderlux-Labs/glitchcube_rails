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
    delegate_to_agents

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

  def delegate_to_agents
    intents = @output.dig("tool_intents")
    return if intents.blank?

    Rails.logger.info "🤖 Delegating #{intents.length} tool intentions to specialized agents"

    # Group intents by domain
    intent_groups = group_intents_by_domain(intents)

    # Delegate to music agent if there are music intents
    if intent_groups[:music].any?
      delegate_to_music_agent(intent_groups[:music])
    end

    # Delegate to general HA agent if there are non-music intents
    if intent_groups[:general].any?
      delegate_to_ha_agent(intent_groups[:general])
    end
  end

  def group_intents_by_domain(intents)
    music_intents = []
    general_intents = []

    intents.each do |intent|
      tool = intent["tool"].to_s.downcase
      if is_music_intent?(tool)
        music_intents << intent
      else
        general_intents << intent
      end
    end

    {
      music: music_intents,
      general: general_intents
    }
  end

  def is_music_intent?(tool)
    music_keywords = %w[music audio sound song track play pause volume spotify]
    music_keywords.any? { |keyword| tool.include?(keyword) }
  end

  def delegate_to_music_agent(music_intents)
    Rails.logger.info "🎵 Delegating #{music_intents.length} music intentions to music agent"

    # Format intentions for music agent
    intent_descriptions = music_intents.map do |intent|
      "#{intent['tool']}: #{intent['intent']}"
    end.join("; ")

    # Create a request that includes context
    music_request = "User asked: \"#{@user_message}\". Please handle music: #{intent_descriptions}"

    Rails.logger.info "🎵 Sending to music agent: #{music_request}"

    # Send to music conversation agent asynchronously
    MusicAgentJob.perform_later(
      request: music_request,
      tool_intents: music_intents,
      session_id: @session_id,
      conversation_id: @conversation_id,
      user_message: @user_message
    )
  end

  def delegate_to_ha_agent(general_intents)
    Rails.logger.info "🏠 Delegating #{general_intents.length} general intentions to HA conversation agent"

    # Format intentions for HA agent
    intent_descriptions = general_intents.map do |intent|
      "#{intent['tool']}: #{intent['intent']}"
    end.join("; ")

    # Create a request that includes context
    ha_request = "User asked: \"#{@user_message}\". Please execute: #{intent_descriptions}"

    Rails.logger.info "🤖 Sending to HA agent: #{ha_request}"

    # Send to HA conversation agent asynchronously
    HaAgentJob.perform_later(
      request: ha_request,
      tool_intents: general_intents,
      session_id: @session_id,
      conversation_id: @conversation_id,
      user_message: @user_message
    )
  end
end
