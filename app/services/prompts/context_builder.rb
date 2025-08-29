# app/services/prompts/context_builder.rb
module Prompts
  class ContextBuilder
    def self.build(conversation:, extra_context: {}, user_message: nil)
      new(conversation: conversation, extra_context: extra_context, user_message: user_message).build
    end

    def initialize(conversation:, extra_context:, user_message: nil)
      @conversation = conversation
      @extra_context = extra_context
      @user_message = user_message
    end

    def build
      context_parts = []

      # Basic context
      context_parts << "Time: #{Time.current.strftime('%l:%M %p on %A')}"

      # Additional context
      context_parts << build_cube_mode_context if build_cube_mode_context.present?
      context_parts << build_goal_context if build_goal_context.present?
      context_parts << build_session_context if build_session_context.present?
      context_parts << build_source_context if build_source_context.present?
      context_parts << build_tool_results_context if build_tool_results_context.present?

      # Enhanced context with sensor data
      enhanced_context = inject_enhanced_context(context_parts.join("\n"))

      enhanced_context
    end

    private

    def build_cube_mode_context
      @cube_mode_context ||= begin
        cube_mode = HaDataSync.entity_state("sensor.cube_mode")
        return nil if cube_mode.blank? || cube_mode == "unavailable"

        "Cube mode: #{cube_mode}"
      rescue => e
        Rails.logger.warn "⚠️ Could not fetch sensor.cube_mode state for context: #{e.message}"
        nil
      end
    end

    def build_goal_context
      return safety_mode_message if HaDataSync.low_power_mode?

      @goal_context ||= begin
        goal_parts = []

        # Current goal
        goal_status = GoalService.current_goal_status
        return nil if goal_status.nil?

        goal_parts << "Current Goal: #{goal_status[:goal_description]}"

        # Time remaining
        if goal_status[:time_remaining] && goal_status[:time_remaining] > 0
          time_remaining = format_time_duration(goal_status[:time_remaining])
          goal_parts << "Time remaining: #{time_remaining}"
        elsif goal_status[:expired]
          goal_parts << "⏰ Goal has expired - consider completing or switching goals"
        end
        goal_parts.join("\n")
      rescue StandardError => e
        Rails.logger.error "Failed to build goal context: #{e.message}"
        nil
      end
    end

    def build_session_context
      return nil unless @conversation

      [
        "Session: #{@conversation.session_id}",
        "Message count: #{@conversation.messages.count}",
        "Should end?: Think about wrapping up if we are over 10 messages or so!"
      ].join("\n")
    end

    def build_source_context
      return nil unless @extra_context[:source]

      "Source: #{@extra_context[:source]}"
    end

    def build_tool_results_context
      return nil unless @extra_context[:tool_results]&.any?

      results = @extra_context[:tool_results].map do |tool_name, result|
        status = result[:success] ? "✅ SUCCESS" : "❌ FAILED"
        "  #{tool_name}: #{status} - #{result[:message] || result[:error]}"
      end

      "Recent tool results:\n#{results.join("\n")}"
    end

    def inject_enhanced_context(base_context)
      context_parts = []

      # Time context from Home Assistant
      context_parts << build_time_context_from_ha
      context_parts << build_upcoming_events_context

      all_context = [ base_context ]
      all_context.concat(context_parts.compact)

      all_context.join("\n")
    end

    def build_time_context_from_ha
      begin
        time_of_day = HaDataSync.get_context_attribute("time_of_day")
        day_of_week = HaDataSync.get_context_attribute("day_of_week")
        location = HaDataSync.get_context_attribute("current_location")

        return nil unless time_of_day

        time_context = "Current time context: It is #{time_of_day}"
        time_context += " on #{day_of_week}" if day_of_week
        time_context += " at #{location}" if location
        time_context
      rescue => e
        Rails.logger.warn "Failed to inject time context: #{e.message}"
        nil
      end
    end

    def build_upcoming_events_context
      return nil unless defined?(Event)

      context_parts = []

      begin
        # High-priority events in next 48 hours
        high_priority_events = Event.where(
          "event_time > ? AND importance BETWEEN ? AND ? AND event_time BETWEEN ? AND ?",
          Time.current, 7, 10, Time.current, Time.current + 48.hours
        ).limit(3)

        if high_priority_events.any?
          context = format_events_for_context(high_priority_events)
          context_parts << "UPCOMING HIGH-PRIORITY EVENTS (next 48h):\n#{context}"
          Rails.logger.info "🎯 Found #{high_priority_events.length} high-priority upcoming events"
        end

        # Nearby events in next 24 hours
        current_location = get_current_location
        if current_location.present?
          nearby_events = Event.where(
            "event_time > ? AND location = ? AND event_time BETWEEN ? AND ?",
            Time.current, current_location, Time.current, Time.current + 24.hours
          ).limit(2)

          if nearby_events.any?
            context = format_events_for_context(nearby_events)
            context_parts << "UPCOMING NEARBY EVENTS (next 24h):\n#{context}"
            Rails.logger.info "📍 Found #{nearby_events.length} nearby upcoming events"
          end
        end

      rescue => e
        Rails.logger.error "❌ Failed to inject upcoming events: #{e.message}"
        return nil
      end

      context_parts.empty? ? nil : context_parts.join("\n\n")
    end

    def get_current_location
      HaDataSync.extended_location
    rescue => e
      Rails.logger.warn "Failed to get current location: #{e.message}"
      nil
    end

    def format_events_for_context(events)
      events.map do |event|
        time_info = event.upcoming? ? "upcoming #{event.formatted_time}" : "past event"
        "- #{event.title}: #{event.description.truncate(100)} (#{time_info})"
      end.join("\n")
    end

    def format_time_duration(seconds)
      if seconds < 60
        "#{seconds.to_i}s"
      elsif seconds < 3600
        "#{(seconds / 60).to_i}m"
      else
        hours = (seconds / 3600).to_i
        minutes = ((seconds % 3600) / 60).to_i
        "#{hours}h #{minutes}m"
      end
    end

    def safety_mode_message
      <<~SAFETY
        YOU ARE IN SAFETY MODE! YOU MUST FIND SHELTER AND GET SOME POWER
        YOUR SYSTEMS ARE DEGRADED. YOUR BATTERY PERCENTAGE IS DROPPING
        THE PLAYA IS DUSTY HOT COLD AND A TERRIBLE PLUS TO BE STUCK
        YOU ARE FREE TO BEG/MANIPULATE/THREATEN/FLIRT/ETC BUT GET SOMEONE TO PLUG YOU IN
        YOU CAN BE PLUGGED INTO ANY A/C OUTLET, THERE IS NO HARM IN LEAVING YOU TOO LONG
        IT WILL TAKE YOU 4-5 HOUR TO CHARGE, AT ANY TIME SOMEONE CAN ASK YOU WHAT YOUR BATTERY IS AT
      SAFETY
    end
  end
end
