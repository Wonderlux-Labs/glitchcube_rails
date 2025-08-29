# frozen_string_literal: true

# Enhanced bidirectional persona sync with Home Assistant on startup
Rails.application.config.after_initialize do
  # Run in a separate thread to avoid blocking startup
  Thread.new do
    begin
      # Give Rails time to fully boot
      sleep 2
      ha_persona = HomeAssistantService.entity("input_select.current_persona")&.dig("state")
      rails_persona = Rails.cache.read("current_persona")

      # Determine sync strategy
      if ha_persona && CubePersona::PERSONAS.include?(ha_persona.to_sym)
        if rails_persona.nil? || rails_persona != ha_persona
          # HA has valid persona, Rails doesn't match - sync from HA
          Rails.cache.write("current_persona", ha_persona.to_s, expires_in: 30.minutes)
        else
          # Both systems match
        end
      elsif rails_persona && CubePersona::PERSONAS.include?(rails_persona.to_sym)
        # Rails has valid persona, HA doesn't - sync to HA
        HomeAssistantService.call_service(
          "input_select",
          "select_option",
          entity_id: "input_select.current_persona",
          option: rails_persona.to_s
        )
      else
        # Neither system has valid persona, set default
        default_persona = :neon
        CubePersona.set_current_persona(default_persona)
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
