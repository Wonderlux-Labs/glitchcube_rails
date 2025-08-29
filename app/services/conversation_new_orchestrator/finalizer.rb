# app/services/conversation_new_orchestrator/finalizer.rb
class ConversationNewOrchestrator::Finalizer
  def self.call(state:, user_message:)
    new(state: state, user_message: user_message).call
  end

  def initialize(state:, user_message:)
    @state = state
    @user_message = user_message
  end

  def call
    tool_analysis = analyze_tools
    store_conversation_log(tool_analysis)
    end_conversation_if_needed(tool_analysis)

    hass_response = format_for_hass(tool_analysis)

    ConversationLogger.conversation_ended(
      @state[:session_id],
      @state[:ai_response][:speech_text],
      continue_conversation?(tool_analysis),
      tool_analysis
    )

    ServiceResult.success({ hass_response: hass_response })
  rescue => e
    ServiceResult.failure("Finalization failed: #{e.message}")
  end

  private

  def analyze_tools
    sync_results = @state.dig(:action_results, :sync_results) || {}
    delegated_intents = @state.dig(:action_results, :delegated_intents) || []

    {
      sync_tools: sync_results.keys,
      async_tools: delegated_intents.map { |intent| intent["tool"] },
      query_tools: sync_results.select { |k, v| k.include?("memory_search") }.keys,
      action_tools: sync_results.keys.select { |tool| tool != "rag_search" }
    }
  end

  def store_conversation_log(tool_analysis)
    # Check if database is available before attempting to create log
    unless ActiveRecord::Base.connected?
      Rails.logger.warn "🗄️ Database not connected - skipping conversation log creation"
      return
    end

    metadata = {
      sync_tools: tool_analysis[:sync_tools],
      async_tools: tool_analysis[:async_tools],
      response_id: @state[:ai_response][:id]
    }

    # Add narrative metadata if available
    if @state[:ai_response]
      metadata.merge!({
        inner_thoughts: @state[:ai_response][:inner_thoughts],
        current_mood: @state[:ai_response][:current_mood],
        pressing_questions: @state[:ai_response][:pressing_questions],
        continue_conversation_from_llm: @state[:ai_response][:continue_conversation],
        goal_progress: @state[:ai_response][:goal_progress]
      })
    end

    begin
      ConversationLog.create!(
        session_id: @state[:session_id],
        user_message: @user_message,
        ai_response: @state[:ai_response][:text],
        tool_results: (@state.dig(:action_results, :sync_results) || {}).to_json,
        metadata: metadata.to_json
      )
      Rails.logger.info "📝 ConversationLog created for session: #{@state[:session_id]}"
    rescue ActiveRecord::ConnectionNotEstablished => e
      Rails.logger.warn "🗄️ Database connection issue - conversation log not saved: #{e.message}"
    rescue => e
      Rails.logger.error "❌ Failed to create conversation log: #{e.message}"
      # Don't re-raise - conversation should continue even if logging fails
    end
  end

  def continue_conversation?(tool_analysis)
    @state.dig(:ai_response, :continue_conversation) || tool_analysis[:async_tools].any?
  end

  def end_conversation_if_needed(tool_analysis)
    return if continue_conversation?(tool_analysis)

    conversation = @state[:conversation]
    return unless conversation&.respond_to?(:active?) && conversation&.respond_to?(:end!)

    begin
      if conversation.active?
        conversation.end!
        Rails.logger.info "🧠 Ended conversation: #{@state[:session_id]}"
      end
    rescue ActiveRecord::ConnectionNotEstablished => e
      Rails.logger.warn "🗄️ Database connection issue - conversation not ended: #{e.message}"
    rescue => e
      Rails.logger.error "❌ Failed to end conversation: #{e.message}"
      # Don't re-raise - finalization should continue
    end
  end

  def format_for_hass(tool_analysis)
    # Determine response type based on tool usage
    response_type = tool_analysis[:async_tools].any? ? "action_done" : "query_answer"

    # Build entity lists for tools
    success_entities = build_success_entities(tool_analysis)
    targets = build_targets(tool_analysis)

    # Use LLM's continue_conversation OR force true if tools pending
    continue_conversation = @state[:ai_response][:continue_conversation] || tool_analysis[:async_tools].any?

    # Create proper ConversationResponse
    conversation_response = ConversationResponse.action_done(
      @state[:ai_response][:text],
      success_entities: success_entities,
      targets: targets,
      continue_conversation: continue_conversation,
      conversation_id: @state[:session_id]
    )

    # Get base response and add end_conversation field
    response = conversation_response.to_home_assistant_response
    response[:end_conversation] = !continue_conversation  # Inverse of continue
    
    # Add configurable delay when continuing conversation
    if continue_conversation
      response[:continue_delay] = Rails.configuration.conversation_continue_delay.to_i
    end

    Rails.logger.info "📤 Response: continue_conversation=#{continue_conversation}, end_conversation=#{!continue_conversation}, continue_delay=#{response[:continue_delay]}"

    response
  end

  def build_success_entities(tool_analysis)
    # For async tools, assume they will succeed (they execute in background)
    tool_analysis[:async_tools].map do |tool_name|
      {
        entity_id: tool_name,
        name: tool_name&.humanize,
        state: "pending" # Will be updated when async job completes
      }
    end
  end

  def build_targets(tool_analysis)
    # Extract entity targets from all tool calls
    all_tools = (tool_analysis[:sync_tools] + tool_analysis[:async_tools])

    all_tools.map do |tool_name|
      # Skip if it's just a string (tool name without arguments)
      next if tool_name.blank?

      {
        entity_id: tool_name,
        name: tool_name.humanize,
        domain: tool_name.split(".").first
      }
    end.compact
  end
end
