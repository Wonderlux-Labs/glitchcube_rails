# app/services/cube_speech.rb
# Convenience class for triggering contextual AI speech

class CubeSpeech
  class << self
    # Quick Deep Playa entry trigger (as per user example)
    def deep_playa_entry(passed_temple: false, **additional_context)
      LocationEventHandler.new.handle_deep_playa_entry(
        passed_temple: passed_temple,
        **additional_context
      )
    end

    # Quick location change trigger
    def location_change(from:, to:, **context)
      LocationEventHandler.handle_location_change(from, to, context)
    end

    # Zone transitions
    def entering_zone(zone_name, **context)
      LocationEventHandler.handle_zone_transition(
        "zone_entry",
        { zone_name: zone_name }.merge(context)
      )
    end

    def leaving_zone(zone_name, **context)
      LocationEventHandler.handle_zone_transition(
        "zone_exit",
        { zone_name: zone_name }.merge(context)
      )
    end

    # Weather events
    def weather_change(from:, to:, severity: "medium", **context)
      LocationEventHandler.new.handle_weather_change(
        {
          from_conditions: from,
          to_conditions: to,
          severity: severity,
          change_type: determine_weather_change_type(from, to)
        }.merge(context)
      )
    end

    # Art proximity
    def near_art(art_name:, **context)
      LocationEventHandler.new.handle_art_proximity(
        { art_name: art_name }.merge(context)
      )
    end

    # System events
    def system_event(event_type:, description:, **context)
      ContextualSpeechTriggerService.trigger_speech(
        trigger_type: "system_event",
        context: {
          event_type: event_type,
          description: description
        }.merge(context)
      )
    end

    # Emergency events
    def emergency(emergency_type:, description:, severity: "high", **context)
      ContextualSpeechTriggerService.trigger_speech(
        trigger_type: "emergency",
        context: {
          emergency_type: emergency_type,
          description: description,
          severity: severity
        }.merge(context),
        force_response: true
      )
    end

    # Time-based events
    def time_milestone(milestone:, **context)
      ContextualSpeechTriggerService.trigger_speech(
        trigger_type: "time_milestone",
        context: {
          milestone: milestone,
          current_time: Time.current.strftime("%l:%M %p on %A")
        }.merge(context)
      )
    end

    # Crowd density changes
    def crowd_change(from_density:, to_density:, **context)
      LocationEventHandler.new.handle_crowd_density_change(
        {
          from_density: from_density,
          to_density: to_density,
          change_type: determine_crowd_change_type(from_density, to_density)
        }.merge(context)
      )
    end

    # Generic contextual trigger
    def contextual_event(trigger_type:, context:, persona: nil, force_response: false)
      ContextualSpeechTriggerService.trigger_speech(
        trigger_type: trigger_type,
        context: context,
        persona: persona,
        force_response: force_response
      )
    end

    # Test speech generation (for development/testing)
    def test_speech(message:, persona: nil)
      contextual_event(
        trigger_type: "system_event",
        context: {
          event_type: "test_trigger",
          description: message,
          test_mode: true
        },
        persona: persona,
        force_response: true
      )
    end

    private

    def determine_weather_change_type(from_conditions, to_conditions)
      # Simple heuristics to categorize weather changes
      from_lower = from_conditions.to_s.downcase
      to_lower = to_conditions.to_s.downcase

      if to_lower.include?("dust") || to_lower.include?("storm")
        "dust_storm"
      elsif to_lower.include?("wind")
        "wind_event"
      elsif from_lower.include?("clear") && to_lower.include?("dust")
        "visibility_change"
      elsif to_lower.include?("extreme") || to_lower.include?("hot") || to_lower.include?("cold")
        "temperature_extreme"
      else
        "general_change"
      end
    end

    def determine_crowd_change_type(from_density, to_density)
      from_level = density_level(from_density)
      to_level = density_level(to_density)

      case [ from_level, to_level ]
      when [ 1, 4 ], [ 1, 5 ], [ 2, 5 ]
        "isolated_to_crowded"
      when [ 4, 1 ], [ 5, 1 ], [ 5, 2 ]
        "crowded_to_isolated"
      when [ 1, 3 ], [ 2, 4 ], [ 3, 5 ]
        "dramatic_increase"
      when [ 5, 3 ], [ 4, 2 ], [ 3, 1 ]
        "dramatic_decrease"
      else
        "gradual_change"
      end
    end

    def density_level(density_description)
      case density_description.to_s.downcase
      when /empty|alone|isolated|nobody/
        1
      when /few|sparse|quiet/
        2
      when /moderate|some|normal/
        3
      when /busy|many|active/
        4
      when /packed|crowded|overwhelming/
        5
      else
        3 # default moderate
      end
    end
  end
end
