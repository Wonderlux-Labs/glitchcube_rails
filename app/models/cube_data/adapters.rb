# frozen_string_literal: true

# CubeData::Adapters - Backward compatibility layer
# This provides adapter methods to help transition from HaDataSync to CubeData
# Can be removed once migration is complete

class CubeData::Adapters < CubeData
  class << self
    # HaDataSync compatibility methods
    # These will log deprecation warnings and delegate to new CubeData methods

    def update_backend_health(status, startup_time = nil)
      deprecation_warning("update_backend_health", "CubeData::System.update_health")
      CubeData::System.update_health(status, startup_time)
    end

    def update_conversation_status(session_id, status, message_count, tools_used = [])
      deprecation_warning("update_conversation_status", "CubeData::Conversation.update_status")
      CubeData::Conversation.update_status(session_id, status, message_count, tools_used)
    end

    def update_world_state(weather_conditions, location_summary, upcoming_events)
      deprecation_warning("update_world_state", "CubeData::WorldState.update_state")
      CubeData::WorldState.update_state(
        weather_conditions: weather_conditions,
        location_summary: location_summary,
        upcoming_events: upcoming_events
      )
    end

    def update_glitchcube_context(time_of_day, location, weather_summary, current_needs = nil)
      deprecation_warning("update_glitchcube_context", "CubeData::WorldState.update_context")
      CubeData::WorldState.update_context(
        time_of_day: time_of_day,
        location: location,
        weather_summary: weather_summary,
        current_needs: current_needs
      )
    end

    def update_current_goal(goal_text, importance, deadline = nil, progress = nil)
      deprecation_warning("update_current_goal", "CubeData::Goals.update_current")
      # Would need to create CubeData::Goals module for goals functionality
      Rails.logger.warn "CubeData::Goals not implemented yet - using legacy HaDataSync call"
      HaDataSync.update_current_goal(goal_text, importance, deadline, progress)
    end

    def update_persona(persona_name, capabilities = [], restrictions = [])
      deprecation_warning("update_persona", "CubeData::Persona.update_current")
      CubeData::Persona.update_current(persona_name, capabilities: capabilities, restrictions: restrictions)
    end

    def update_location(lat, lng, location_name, accuracy = nil)
      deprecation_warning("update_location", "CubeData::Location.update_location")
      CubeData::Location.update_location(lat, lng, location_name, accuracy: accuracy)
    end

    def update_proximity(nearby_landmarks, distance_to_landmarks = {})
      deprecation_warning("update_proximity", "CubeData::Location.update_proximity")
      CubeData::Location.update_proximity(nearby_landmarks, distance_to_landmarks)
    end

    def update_last_tool_execution(tool_name, success, execution_time, parameters = {})
      deprecation_warning("update_last_tool_execution", "CubeData::Tools.record_execution")
      CubeData::Tools.record_execution(tool_name, success, execution_time, parameters)
    end

    def update_memory_stats(total_memories, recent_extractions, last_extraction_time)
      deprecation_warning("update_memory_stats", "CubeData::Memory.update_stats")
      CubeData::Memory.update_stats(total_memories, recent_extractions, last_extraction_time)
    end

    def update_breaking_news(message, expires_at = nil)
      deprecation_warning("update_breaking_news", "CubeData::Events.update_breaking_news")
      CubeData::Events.update_breaking_news(message, expires_at)
    end

    def get_breaking_news
      deprecation_warning("get_breaking_news", "CubeData::Events.breaking_news")
      CubeData::Events.breaking_news
    end

    def clear_breaking_news
      deprecation_warning("clear_breaking_news", "CubeData::Events.clear_breaking_news")
      CubeData::Events.clear_breaking_news
    end

    def update_cube_mode(mode, trigger_source = nil)
      deprecation_warning("update_cube_mode", "CubeData::Mode.update_mode")
      CubeData::Mode.update_mode(mode, trigger_source)
    end

    def get_current_mode
      deprecation_warning("get_current_mode", "CubeData::Mode.get_current_mode")
      CubeData::Mode.get_current_mode
    end

    def low_power_mode?
      deprecation_warning("low_power_mode?", "CubeData::Mode.low_power_mode?")
      CubeData::Mode.low_power_mode?
    end

    def enter_low_power_mode(trigger_source = "battery_low")
      deprecation_warning("enter_low_power_mode", "CubeData::Mode.enter_low_power_mode")
      CubeData::Mode.enter_low_power_mode(trigger_source)
    end

    def exit_low_power_mode(trigger_source = "battery_restored")
      deprecation_warning("exit_low_power_mode", "CubeData::Mode.exit_low_power_mode")
      CubeData::Mode.exit_low_power_mode(trigger_source)
    end

    # Entity reading methods
    def entity(entity_id)
      deprecation_warning("entity", "CubeData.read_sensor")
      CubeData.read_sensor(entity_id)
    end

    def entity_state(entity_id)
      deprecation_warning("entity_state", "CubeData.read_sensor(id)['state']")
      sensor_data = CubeData.read_sensor(entity_id)
      sensor_data&.dig("state")
    end

    def entity_attribute(entity_id, attribute_path)
      deprecation_warning("entity_attribute", "CubeData.read_sensor(id)['attributes'][attr]")
      sensor_data = CubeData.read_sensor(entity_id)
      return nil unless sensor_data

      if attribute_path.is_a?(Array)
        attribute_path.reduce(sensor_data) { |data, key| data&.dig(key) }
      else
        sensor_data.dig("attributes", attribute_path)
      end
    end

    def get_context_data
      deprecation_warning("get_context_data", "CubeData::WorldState.context")
      CubeData::WorldState.context
    end

    def get_context_attribute(attribute)
      deprecation_warning("get_context_attribute", "CubeData::WorldState.context_attribute")
      CubeData::WorldState.context_attribute(attribute)
    end

    def get_location_context
      deprecation_warning("get_location_context", "CubeData::Location.context")
      CubeData::Location.context
    end

    def get_location_context_attribute(attribute)
      deprecation_warning("get_location_context_attribute", "CubeData::Location.context_attribute")
      CubeData::Location.context_attribute(attribute)
    end

    # Extended location - compatibility method
    def extended_location
      deprecation_warning("extended_location", "CubeData::Location.extended_location_string")
      CubeData::Location.extended_location_string
    end

    private

    def deprecation_warning(old_method, new_method)
      Rails.logger.warn "[DEPRECATION] HaDataSync.#{old_method} is deprecated. Use #{new_method} instead."

      # In development, also log to console
      if Rails.env.development?
        puts "\n⚠️  DEPRECATION WARNING: HaDataSync.#{old_method} is deprecated."
        puts "   Use #{new_method} instead."
        puts "   Called from: #{caller(2).first}\n\n"
      end
    end
  end
end

# Create a compatibility class that delegates to CubeData::Adapters
# This allows existing code using HaDataSync to work without changes
# while showing deprecation warnings

class HaDataSyncCompat < CubeData::Adapters
  def self.method_missing(method_name, *args, &block)
    if CubeData::Adapters.respond_to?(method_name)
      CubeData::Adapters.send(method_name, *args, &block)
    else
      # Fall back to original HaDataSync for methods not yet migrated
      Rails.logger.warn "[COMPATIBILITY] Method #{method_name} not found in CubeData, falling back to HaDataSync"
      HaDataSync.send(method_name, *args, &block)
    end
  end

  def self.respond_to_missing?(method_name, include_private = false)
    CubeData::Adapters.respond_to?(method_name, include_private) ||
      HaDataSync.respond_to?(method_name, include_private) ||
      super
  end
end
