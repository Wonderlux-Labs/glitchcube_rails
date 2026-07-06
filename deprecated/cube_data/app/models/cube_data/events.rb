# frozen_string_literal: true

class CubeData::Events < CubeData
  class << self
    # Update breaking news
    def update_breaking_news(message, expires_at = nil)
      write_sensor(sensor_id(:events, :breaking_news), message)

      # Schedule clearing if expiration is set
      if expires_at
        # This would need a job class to be created
        # ClearBreakingNewsJob.set(wait_until: expires_at).perform_later
      end

      Rails.logger.info "📢 Breaking news updated: #{message.truncate(50)}"
    end

    # Clear breaking news
    def clear_breaking_news
      write_sensor(sensor_id(:events, :breaking_news), "")
      Rails.logger.info "📢 Breaking news cleared"
    end

    # Record last event
    def record_event(event_type, description, importance = 5, metadata = {})
      write_sensor(
        sensor_id(:events, :last_event),
        event_type,
        {
          event_type: event_type,
          description: description,
          importance: importance,
          occurred_at: Time.current.iso8601,
          **metadata
        }
      )

      Rails.logger.info "📅 Event recorded: #{event_type}"
    end

    # Update upcoming events
    def update_upcoming_events(events_list)
      formatted_events = events_list.map do |event|
        {
          title: event[:title] || event["title"],
          start_time: event[:start_time] || event["start_time"],
          importance: event[:importance] || event["importance"] || 5,
          location: event[:location] || event["location"]
        }
      end

      write_sensor(
        sensor_id(:events, :upcoming),
        formatted_events.count,
        {
          events: formatted_events,
          last_updated: Time.current.iso8601
        }
      )

      Rails.logger.info "📅 Upcoming events updated: #{formatted_events.count} events"
    end

    # Get breaking news
    def breaking_news
      news_data = read_sensor(sensor_id(:events, :breaking_news))
      news = news_data&.dig("state")

      # Return nil if empty or just brackets (legacy format)
      return nil if news.blank? || news.strip == "[]"

      news
    end

    # Check if there's active breaking news
    def has_breaking_news?
      breaking_news.present?
    end

    # Get last event
    def last_event
      read_sensor(sensor_id(:events, :last_event))
    end

    # Get last event type
    def last_event_type
      event = last_event
      event&.dig("state")
    end

    # Get last event description
    def last_event_description
      event = last_event
      event&.dig("attributes", "description")
    end

    # Get last event time
    def last_event_time
      event = last_event
      timestamp = event&.dig("attributes", "occurred_at")
      timestamp ? Time.parse(timestamp) : nil
    rescue
      nil
    end

    # Get upcoming events
    def upcoming_events
      read_sensor(sensor_id(:events, :upcoming))
    end

    # Get upcoming events list
    def upcoming_events_list
      events_data = upcoming_events
      events_data&.dig("attributes", "events") || []
    end

    # Get count of upcoming events
    def upcoming_events_count
      events_data = upcoming_events
      events_data&.dig("state")&.to_i || 0
    end

    # Get upcoming events by importance
    def upcoming_events_by_importance(min_importance = 7)
      upcoming_events_list.select do |event|
        (event["importance"] || 5) >= min_importance
      end
    end

    # Get next upcoming event
    def next_event
      events = upcoming_events_list
      return nil if events.empty?

      # Sort by start_time and get the next one
      sorted_events = events.sort_by { |e| Time.parse(e["start_time"]) rescue Time.current + 1.year }
      sorted_events.find { |e| Time.parse(e["start_time"]) > Time.current rescue false }
    end

    # Check if there are important upcoming events
    def has_important_upcoming_events?(min_importance = 8)
      upcoming_events_by_importance(min_importance).any?
    end

    # Check if there were recent events
    def recent_event?(within = 1.hour)
      last_time = last_event_time
      return false unless last_time

      last_time > within.ago
    end

    # Get events summary
    def summary
      {
        breaking_news: has_breaking_news?,
        breaking_news_text: breaking_news,
        last_event: last_event_type,
        upcoming_count: upcoming_events_count,
        important_upcoming: upcoming_events_by_importance(8).count,
        next_event: next_event
      }
    end
  end
end
