# frozen_string_literal: true

# Sync persona state with Home Assistant on startup
Rails.application.config.after_initialize do
  # Run in a separate thread to avoid blocking startup
  Thread.new do
    begin
      # Give Rails time to fully boot
      sleep 2

      Rails.logger.info "🎭 Initializing persona sync with Home Assistant"

      # Get the current persona from HA
      ha_persona = HomeAssistantService.entity("input_select.current_persona")&.dig("state")

      if ha_persona && CubePersona::PERSONAS.include?(ha_persona.to_sym)
        # HA has a valid persona, cache it
        Rails.cache.write("current_persona", ha_persona.to_s, expires_in: 10.minutes)
        Rails.logger.info "🎭 Synced persona from HA: #{ha_persona}"
      else
        # HA doesn't have a valid persona, set it to neon (current default)
        default_persona = :neon
        CubePersona.set_current_persona(default_persona)
        Rails.logger.info "🎭 Set default persona in HA: #{default_persona}"
      end

    rescue StandardError => e
      Rails.logger.error "❌ Failed to sync persona on startup: #{e.message}"
      # Fallback to cache with neon default
      Rails.cache.write("current_persona", "neon", expires_in: 10.minutes)
    end
  end
end
