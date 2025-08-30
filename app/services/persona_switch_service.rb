# app/services/persona_switch_service.rb

class PersonaSwitchService
  class << self
    # Handle persona switching - end current conversation and notify Home Assistant
    def handle_persona_switch(new_persona_id, previous_persona_id = nil)
      Rails.logger.info "🎭 Persona switch: #{previous_persona_id || 'unknown'} → #{new_persona_id}"
      
      begin
        # End any active conversations to ensure new conversation starts fresh
        end_active_conversations
        
        # Clear any cached conversation data
        clear_conversation_caches
        
        # Notify Home Assistant of the persona change
        HomeAssistantService.call_service(
          "input_text",
          "set_value",
          {
            entity_id: "input_text.current_persona",
            value: new_persona_id.to_s
          }
        )
        
        Rails.logger.info "✅ Notified Home Assistant of persona change to #{new_persona_id}"
      rescue StandardError => e
        Rails.logger.error "❌ Failed to notify Home Assistant: #{e.message}"
      end
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
