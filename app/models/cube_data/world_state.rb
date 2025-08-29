# frozen_string_literal: true

class CubeData::WorldState < CubeData
  class << self
    # Update main world state sensor
    def update_state(weather_conditions: nil, location_summary: nil, upcoming_events: nil, additional_attrs: {})
      current_state = read_sensor(sensor_id(:world, :state))
      current_attributes = current_state&.dig("attributes") || {}

      new_attributes = current_attributes.merge({
        last_updated: Time.current.iso8601,
        **additional_attrs
      })

      new_attributes["weather_conditions"] = weather_conditions if weather_conditions
      new_attributes["location_summary"] = location_summary if location_summary
      new_attributes["upcoming_events"] = upcoming_events if upcoming_events

      write_sensor(sensor_id(:world, :state), "active", new_attributes)
      Rails.logger.info "🌍 World state updated"
    end

    # Update weather conditions specifically
    def update_weather(weather_summary)
      update_state(weather_conditions: weather_summary)

      # Also update dedicated weather sensor
      write_sensor(
        sensor_id(:world, :weather),
        weather_summary,
        {
          updated_at: Time.current.iso8601
        }
      )

      Rails.logger.info "🌤️ Weather updated: #{weather_summary.truncate(50)}"
    end

    # Update context sensor with time, location, and environment data
    def update_context(time_of_day: nil, location: nil, weather_summary: nil, current_needs: nil)
      attributes = {
        last_updated: Time.current.iso8601
      }

      attributes[:time_of_day] = time_of_day if time_of_day
      attributes[:current_location] = location if location
      attributes[:weather_summary] = weather_summary if weather_summary
      attributes[:current_needs] = current_needs if current_needs

      write_sensor(sensor_id(:world, :context), "active", attributes)
      Rails.logger.info "🎯 Context updated"
    end

    # Update time-specific context
    def update_time_context(time_of_day, day_of_week, is_weekend: false, special_occasion: nil)
      write_sensor(
        sensor_id(:world, :time_context),
        time_of_day,
        {
          time_of_day: time_of_day,
          day_of_week: day_of_week,
          is_weekend: is_weekend,
          special_occasion: special_occasion,
          last_updated: Time.current.iso8601
        }
      )

      Rails.logger.debug "⏰ Time context updated: #{time_of_day}"
    end

    # Read world state
    def current_state
      read_sensor(sensor_id(:world, :state))
    end

    # Get weather conditions
    def weather_conditions
      state = current_state
      state&.dig("attributes", "weather_conditions")
    end

    # Get context data
    def context
      read_sensor(sensor_id(:world, :context))
    end

    # Get specific context attribute
    def context_attribute(attribute)
      context_data = context
      context_data&.dig("attributes", attribute)
    end

    # Get time of day from context
    def time_of_day
      context_attribute("time_of_day")
    end

    # Get current location from context
    def current_location
      context_attribute("current_location")
    end

    # Get weather summary from context
    def weather_summary
      context_attribute("weather_summary") || weather_conditions
    end

    # Check if world state is active/healthy
    def active?
      state = current_state
      state&.dig("state") == "active"
    end

    # Get last update time
    def last_updated
      state = current_state
      timestamp = state&.dig("attributes", "last_updated")
      timestamp ? Time.parse(timestamp) : nil
    rescue
      nil
    end

    # Check if data is stale (older than specified time)
    def stale?(max_age = 1.hour)
      last_update = last_updated
      return true unless last_update

      last_update < max_age.ago
    end
  end
end
