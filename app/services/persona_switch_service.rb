# app/services/persona_switch_service.rb

class PersonaSwitchService
  class << self
    # Rails-side bookkeeping for a persona switch. The actual input_select.current_persona
    # write is owned by the caller (CubePersona.set_current_persona — directly or via the
    # set_persona_{grand,quick} HASS script), so this method does not touch HASS state.
    def handle_persona_switch(new_persona_id, previous_persona_id = nil)
      Rails.logger.info "🎭 Persona switch: #{previous_persona_id || 'unknown'} → #{new_persona_id}"

      # Summarize the OUTGOING persona's just-finished stint (memory + self-steering).
      PersonaSummarizerJob.perform_later(previous_persona_id.to_s) if previous_persona_id.present?

      # End any active conversations to ensure new conversation starts fresh
      end_active_conversations

      # Clear any cached conversation data
      clear_conversation_caches
    end

    private

    def end_active_conversations
      # End all active conversations to ensure fresh start with new persona
      active_conversations = Conversation.active
      active_conversations.each do |conversation|
        Rails.logger.info "📝 Ending conversation #{conversation.session_id} due to persona change"
        conversation.end!
      end
      Rails.logger.info "✅ Ended #{active_conversations.count} active conversations"
    end

    def clear_conversation_caches
      # Clear any cached conversation-related data
      Rails.cache.delete_matched("conversation:*") if Rails.cache.respond_to?(:delete_matched)
      Rails.cache.delete_matched("performance_mode:*") if Rails.cache.respond_to?(:delete_matched)
      Rails.logger.info "🧹 Cleared conversation caches"
    end
  end
end
