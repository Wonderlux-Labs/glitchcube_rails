# app/services/conversation_new_orchestrator/setup.rb
class ConversationNewOrchestrator::Setup
  def self.call(session_id:, context:)
    new(session_id: session_id, context: context).call
  end

  def initialize(session_id:, context:)
    @session_id = session_id
    @context = context
  end

  def call
    return ServiceResult.failure("Setup failed: session_id is required") if @session_id.nil?
    return ServiceResult.failure("Setup failed: session_id is required") if @session_id.blank?
    return ServiceResult.failure("Setup failed: context is required") if @context.nil?

    persona = determine_persona
    return ServiceResult.failure("Setup failed: No current persona found") if persona.nil?

    conversation = find_or_create_conversation

    # Update conversation with current persona if it's new
    conversation.update!(persona: persona) if conversation.new_record? || conversation.persona.blank?

    ServiceResult.success({
      conversation: conversation,
      persona: persona,
      session_id: @session_id # session_id might change if the old one was stale
    })
  rescue => e
    ServiceResult.failure("Setup failed: #{e.message}")
  end

  private

  def find_or_create_conversation
    conversation = Conversation.find_by(session_id: @session_id)

    if conversation_is_stale?(conversation)
      end_stale_conversation(conversation)
      @session_id = generate_new_session_id
      conversation = nil # Force creation of a new one
    end

    conversation || Conversation.create!(
      session_id: @session_id,
      started_at: Time.current,
      metadata_json: build_initial_metadata
    )
  end

  def conversation_is_stale?(conversation)
    return false unless conversation&.conversation_logs&.any?
    last_message_time = conversation.conversation_logs.maximum(:created_at)
    last_message_time && last_message_time < Rails.configuration.conversation_stale_timeout.ago
  end

  def end_stale_conversation(conversation)
    Rails.logger.info "🕒 Session #{conversation.session_id} is stale, ending it."
    conversation.end! if conversation.active?
  end

  def generate_new_session_id
    original_id = @session_id.split("_stale_").first
    new_id = "#{original_id}_stale_#{Time.current.to_i}"
    Rails.logger.info "🆕 New session ID due to staleness: #{new_id}"
    new_id
  end

  def determine_persona
    # Context override primarily for testing/dev purposes
    if @context[:persona].present? && @context[:persona] != CubePersona.current_persona
      Rails.logger.warn "🎭 Persona override in context: using #{@context[:persona]}"
      @context[:persona]
    else
      # Always get fresh persona from system, not cache
      current = CubePersona.current_persona
      Rails.logger.info "🎭 Current persona determined: #{current}"
      current
    end
  end

  def build_initial_metadata
    {
      agent_id: @context[:agent_id],
      device_id: @context[:device_id],
      source: @context[:source],
      original_session_id: @session_id.split("_stale_").first
    }.compact
  end
end
