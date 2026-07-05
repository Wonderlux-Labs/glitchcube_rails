# app/services/conversation_orchestrator/finalizer.rb
class ConversationOrchestrator::Finalizer
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
      tool_analysis,
      {
        inner_monologue: @state[:ai_response][:inner_monologue],
        actions: @state[:ai_response][:actions]
      }
    )

    ServiceResult.success({ hass_response: hass_response })
  rescue => e
    ServiceResult.failure("Finalization failed: #{e.message}")
  end

  private

  def analyze_tools
    {
      sync_tools: [],
      environment_dispatched: @state.dig(:action_results, :dispatched_environment) || false
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
      environment_dispatched: tool_analysis[:environment_dispatched],
      response_id: @state[:ai_response][:id]
    }

    # Add narrative metadata if available
    if @state[:ai_response]
      metadata.merge!({
        inner_monologue: @state[:ai_response][:inner_monologue],
        continue_conversation_from_llm: @state[:ai_response][:continue_conversation],
        actions: @state[:ai_response][:actions]
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
    @state.dig(:ai_response, :continue_conversation) || tool_analysis[:environment_dispatched]
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
    # No real entity names available — environment instruction is opaque plain-English
    success_entities = []
    targets = []

    # Use LLM's continue_conversation OR force true if environment job was dispatched
    continue_conversation = @state[:ai_response][:continue_conversation] || tool_analysis[:environment_dispatched]

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

    # Add hardcoded 3 second delay when continuing conversation
    if continue_conversation
      response[:continue_delay] = 3
    end

    Rails.logger.info "📤 Response: continue_conversation=#{continue_conversation}, end_conversation=#{!continue_conversation}, continue_delay=#{response[:continue_delay]}"

    response
  end
end
