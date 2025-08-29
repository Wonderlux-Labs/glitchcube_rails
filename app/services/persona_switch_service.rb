# app/services/persona_switch_service.rb

class PersonaSwitchService
  class << self
    # Handle persona switching - just notify Home Assistant
    def handle_persona_switch(new_persona_id, previous_persona_id = nil)
      Rails.logger.info "🎭 Persona switch: #{previous_persona_id || 'unknown'} → #{new_persona_id}"
      
      begin
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
  end
end
