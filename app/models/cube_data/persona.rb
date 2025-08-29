# frozen_string_literal: true

class CubeData::Persona < CubeData
  class << self
    # Update current persona
    def update_current(persona_name, capabilities: [], restrictions: [], additional_info: {})
      # Update persona selector
      write_sensor(sensor_id(:persona, :current), persona_name)

      # Update persona details sensor
      write_sensor(
        sensor_id(:persona, :details),
        persona_name,
        {
          capabilities: capabilities,
          restrictions: restrictions,
          last_updated: Time.current.iso8601,
          **additional_info
        }
      )

      # Record the switch
      record_switch(persona_name)

      Rails.logger.info "🎭 Persona updated: #{persona_name}"
    end

    # Record persona switch for tracking
    def record_switch(persona_name, trigger_source = nil)
      write_sensor(
        sensor_id(:persona, :last_switch),
        persona_name,
        {
          persona: persona_name,
          switched_at: Time.current.iso8601,
          trigger_source: trigger_source
        }
      )
    end

    # Update persona capabilities
    def update_capabilities(capabilities)
      current_persona = get_current_name
      return false unless current_persona

      details = current_details
      current_attrs = details&.dig("attributes") || {}

      write_sensor(
        sensor_id(:persona, :details),
        current_persona,
        current_attrs.merge({
          capabilities: capabilities,
          last_updated: Time.current.iso8601
        })
      )

      Rails.logger.info "🎭 Persona capabilities updated: #{capabilities.count} items"
    end

    # Get current persona name
    def get_current_name
      current_data = read_sensor(sensor_id(:persona, :current))
      current_data&.dig("state")
    end

    # Get current persona details
    def current_details
      read_sensor(sensor_id(:persona, :details))
    end

    # Get persona capabilities
    def capabilities
      details = current_details
      details&.dig("attributes", "capabilities") || []
    end

    # Get persona restrictions
    def restrictions
      details = current_details
      details&.dig("attributes", "restrictions") || []
    end

    # Check if persona has specific capability
    def has_capability?(capability)
      capabilities.include?(capability.to_s)
    end

    # Check if persona has restriction
    def has_restriction?(restriction)
      restrictions.include?(restriction.to_s)
    end

    # Get last persona switch info
    def last_switch
      read_sensor(sensor_id(:persona, :last_switch))
    end

    # Get when persona was last switched
    def last_switch_time
      switch_data = last_switch
      timestamp = switch_data&.dig("attributes", "switched_at")
      timestamp ? Time.parse(timestamp) : nil
    rescue
      nil
    end

    # Check if persona was switched recently
    def recently_switched?(within = 1.minute)
      last_time = last_switch_time
      return false unless last_time

      last_time > within.ago
    end

    # List available personas (would need to be configured)
    def available_personas
      # This could read from HA or be configured elsewhere
      %w[buddy crash jax mobius neon sparkle thecube zorp]
    end

    # Check if persona name is valid
    def valid_persona?(name)
      available_personas.include?(name.to_s.downcase)
    end
  end
end
