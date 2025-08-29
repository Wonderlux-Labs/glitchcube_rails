# frozen_string_literal: true

class CubeData::Mode < CubeData
  class << self
    # Update cube mode
    def update_mode(mode, trigger_source = nil, additional_info = {})
      # Get previous mode for tracking
      previous_mode = get_current_mode

      # Update mode selector
      write_sensor(sensor_id(:mode, :current), mode)

      # Update mode info sensor with metadata
      write_sensor(
        sensor_id(:mode, :info),
        mode,
        {
          mode: mode,
          changed_by: trigger_source,
          changed_at: Time.current.iso8601,
          previous_mode: previous_mode,
          **additional_info
        }
      )

      Rails.logger.info "🎭 Cube mode changed to: #{mode} (via #{trigger_source})"
    end

    # Enter low power mode
    def enter_low_power_mode(trigger_source = "battery_low")
      update_mode("low_power", trigger_source)

      # Update low power binary sensor if it exists
      if sensor_exists?(:mode, :low_power)
        write_sensor(sensor_id(:mode, :low_power), "on")
      end
    end

    # Exit low power mode
    def exit_low_power_mode(trigger_source = "battery_restored")
      update_mode("conversation", trigger_source)

      # Update low power binary sensor if it exists
      if sensor_exists?(:mode, :low_power)
        write_sensor(sensor_id(:mode, :low_power), "off")
      end
    end

    # Update battery level
    def update_battery_level(level)
      write_sensor(sensor_id(:mode, :battery), level.to_s)

      # Auto-enter low power mode if battery is critical
      if level.to_i <= 10
        enter_low_power_mode("critical_battery")
      elsif level.to_i >= 20 && low_power_mode?
        exit_low_power_mode("battery_recovered")
      end

      Rails.logger.debug "🔋 Battery level updated: #{level}%"
    end

    # Get current mode
    def get_current_mode
      mode_data = read_sensor(sensor_id(:mode, :current))
      mode_data&.dig("state") || "conversation"
    end

    # Get mode info/metadata
    def mode_info
      read_sensor(sensor_id(:mode, :info))
    end

    # Check if in low power mode
    def low_power_mode?
      current_mode = get_current_mode
      current_mode == "low_power" || current_mode == "battery_low"
    end

    # Check if in performance mode
    def performance_mode?
      # Check performance mode binary sensor if it exists
      perf_data = read_sensor(sensor_id(:performance, :mode))
      return perf_data&.dig("state") == "on" if perf_data

      # Fallback to checking mode
      get_current_mode == "performance"
    end

    # Get battery level
    def battery_level
      battery_data = read_sensor(sensor_id(:mode, :battery))
      battery_data&.dig("state")&.to_i || 100
    end

    # Check if battery is low
    def battery_low?
      battery_level <= 20
    end

    # Check if battery is critical
    def battery_critical?
      battery_level <= 10
    end

    # Get when mode was last changed
    def last_mode_change
      info = mode_info
      timestamp = info&.dig("attributes", "changed_at")
      timestamp ? Time.parse(timestamp) : nil
    rescue
      nil
    end

    # Get what triggered the last mode change
    def last_mode_trigger
      info = mode_info
      info&.dig("attributes", "changed_by")
    end

    # Get previous mode
    def previous_mode
      info = mode_info
      info&.dig("attributes", "previous_mode")
    end

    # Check if mode changed recently
    def mode_changed_recently?(within = 5.minutes)
      last_change = last_mode_change
      return false unless last_change

      last_change > within.ago
    end

    # Available modes
    def available_modes
      %w[conversation low_power performance sleep maintenance]
    end

    # Check if mode is valid
    def valid_mode?(mode)
      available_modes.include?(mode.to_s)
    end
  end
end
