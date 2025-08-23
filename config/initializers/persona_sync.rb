# frozen_string_literal: true

# Enhanced bidirectional persona sync with Home Assistant on startup
Rails.application.config.after_initialize do
  # Run in a separate thread to avoid blocking startup
  Thread.new do
    begin
      # Give Rails time to fully boot
      sleep 2

      Rails.logger.info "🎭 Initializing bidirectional persona sync with Home Assistant"

      # Get current state from both systems
      ha_persona = HomeAssistantService.entity("input_select.current_persona")&.dig("state")
      rails_persona = Rails.cache.read("current_persona")

      Rails.logger.info "🔄 Current state - HA: #{ha_persona || 'none'}, Rails: #{rails_persona || 'none'}"

      # Determine sync strategy
      if ha_persona && CubePersona::PERSONAS.include?(ha_persona.to_sym)
        if rails_persona.nil? || rails_persona != ha_persona
          # HA has valid persona, Rails doesn't match - sync from HA
          Rails.cache.write("current_persona", ha_persona.to_s, expires_in: 30.minutes)
          Rails.logger.info "📥 Synced persona FROM HA: #{ha_persona}"
        else
          # Both systems match
          Rails.logger.info "✅ Persona already synchronized: #{ha_persona}"
        end
      elsif rails_persona && CubePersona::PERSONAS.include?(rails_persona.to_sym)
        # Rails has valid persona, HA doesn't - sync to HA
        HomeAssistantService.call_service(
          "input_select",
          "select_option",
          entity_id: "input_select.current_persona",
          option: rails_persona.to_s
        )
        Rails.logger.info "📤 Synced persona TO HA: #{rails_persona}"
      else
        # Neither system has valid persona, set default
        default_persona = :neon
        CubePersona.set_current_persona(default_persona)
        Rails.logger.info "🎭 Set default persona for both systems: #{default_persona}"
      end

      # Extend cache expiration for stability
      current = Rails.cache.read("current_persona") || "neon"
      Rails.cache.write("current_persona", current, expires_in: 30.minutes)

    rescue StandardError => e
      Rails.logger.error "❌ Failed to sync persona on startup: #{e.message}"
      # Fallback to cache with neon default
      Rails.cache.write("current_persona", "neon", expires_in: 30.minutes)
    end
  end
end
