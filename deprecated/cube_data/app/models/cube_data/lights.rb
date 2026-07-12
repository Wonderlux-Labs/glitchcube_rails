# frozen_string_literal: true

class CubeData::Lights < CubeData
  class << self
    # Turn on lights with optional parameters
    def turn_on(entity_id, brightness: nil, color: nil, effect: nil, transition: nil)
      light_id = normalize_light_id(entity_id)

      service_data = { entity_id: light_id }
      service_data[:brightness] = brightness if brightness
      service_data[:rgb_color] = color if color
      service_data[:effect] = effect if effect
      service_data[:transition] = transition if transition

      result = call_service("light", "turn_on", service_data)

      Rails.logger.info "💡 Light turned on: #{light_id}"
      result
    end

    # Turn off lights
    def turn_off(entity_id, transition: nil)
      light_id = normalize_light_id(entity_id)

      service_data = { entity_id: light_id }
      service_data[:transition] = transition if transition

      result = call_service("light", "turn_off", service_data)

      Rails.logger.info "💡 Light turned off: #{light_id}"
      result
    end

    # Toggle lights
    def toggle(entity_id)
      light_id = normalize_light_id(entity_id)

      result = call_service("light", "toggle", { entity_id: light_id })

      Rails.logger.info "💡 Light toggled: #{light_id}"
      result
    end

    # Set light effect
    def set_effect(entity_id, effect_name)
      turn_on(entity_id, effect: effect_name)
    end

    # Set light brightness (0-255)
    def set_brightness(entity_id, brightness)
      turn_on(entity_id, brightness: brightness)
    end

    # Set light color (RGB array [r, g, b])
    def set_color(entity_id, rgb_color)
      turn_on(entity_id, color: rgb_color)
    end

    # Get light state
    def get_state(entity_id)
      light_id = normalize_light_id(entity_id)
      read_sensor(light_id, cache_ttl: 1.second) # Lights change frequently, short cache
    end

    # Check if light is on
    def on?(entity_id)
      state = get_state(entity_id)
      state&.dig("state") == "on"
    end

    # Check if light is off
    def off?(entity_id)
      !on?(entity_id)
    end

    # Get light brightness (0-255)
    def brightness(entity_id)
      state = get_state(entity_id)
      state&.dig("attributes", "brightness")&.to_i || 0
    end

    # Get light color
    def color(entity_id)
      state = get_state(entity_id)
      state&.dig("attributes", "rgb_color")
    end

    # Get current effect
    def current_effect(entity_id)
      state = get_state(entity_id)
      state&.dig("attributes", "effect")
    end

    # Get available effects for a light
    def available_effects(entity_id)
      state = get_state(entity_id)
      state&.dig("attributes", "effect_list") || []
    end

    # Get all light states
    def all_states
      {
        top: get_state(:top),
        inner: get_state(:inner)
      }
    end

    # Turn on all cube lights
    def all_on(brightness: nil, color: nil, effect: nil, transition: nil)
      [ sensor_id(:lights, :top), sensor_id(:lights, :inner) ].each do |light|
        turn_on(light, brightness: brightness, color: color, effect: effect, transition: transition)
      end
    end

    # Turn off all cube lights
    def all_off(transition: nil)
      [ sensor_id(:lights, :top), sensor_id(:lights, :inner) ].each do |light|
        turn_off(light, transition: transition)
      end
    end

    # Set synchronized effect on all lights
    def sync_effect(effect_name, brightness: nil, transition: nil)
      all_on(brightness: brightness, effect: effect_name, transition: transition)
    end

    # Set synchronized color on all lights
    def sync_color(rgb_color, brightness: nil, transition: nil)
      all_on(brightness: brightness, color: rgb_color, transition: transition)
    end

    # Check if all lights are on
    def all_on?
      on?(:top) && on?(:inner)
    end

    # Check if all lights are off
    def all_off?
      off?(:top) && off?(:inner)
    end

    private

    # Normalize light entity ID (convert symbol to full entity ID)
    def normalize_light_id(entity_id)
      case entity_id.to_sym
      when :top
        sensor_id(:lights, :top)
      when :inner
        sensor_id(:lights, :inner)
      when :all
        sensor_id(:lights, :all)
      else
        entity_id.to_s
      end
    end
  end
end
