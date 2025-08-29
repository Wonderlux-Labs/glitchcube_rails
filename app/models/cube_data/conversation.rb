# frozen_string_literal: true

class CubeData::Conversation < CubeData
  class << self
    # Update conversation status
    def update_status(session_id, status, message_count = 0, tools_used = [], metadata = {})
      write_sensor(
        sensor_id(:conversation, :status),
        status,
        {
          session_id: session_id,
          message_count: message_count,
          tools_used: tools_used,
          last_updated: Time.current.iso8601,
          **metadata
        }
      )

      Rails.logger.info "💬 Conversation status updated: #{session_id} - #{status}"
    end

    # Update active conversation count
    def update_active_count(count)
      write_sensor(
        sensor_id(:conversation, :active_count),
        count,
        {
          last_updated: Time.current.iso8601
        }
      )

      Rails.logger.debug "💬 Active conversation count: #{count}"
    end

    # Update daily conversation stats
    def update_daily_stats(total_today, avg_response_time = nil)
      write_sensor(
        sensor_id(:conversation, :total_today),
        total_today,
        {
          date: Date.current.iso8601,
          last_updated: Time.current.iso8601
        }
      )

      if avg_response_time
        write_sensor(
          sensor_id(:conversation, :response_time),
          avg_response_time.round(2),
          {
            unit: "seconds",
            last_calculated: Time.current.iso8601
          }
        )
      end

      Rails.logger.info "💬 Daily stats updated: #{total_today} conversations"
    end

    # Record last session details
    def record_last_session(session_id, duration, message_count, persona, ended_at = nil)
      write_sensor(
        sensor_id(:conversation, :last_session),
        session_id,
        {
          duration: duration&.round(2),
          message_count: message_count,
          persona: persona,
          ended_at: (ended_at || Time.current).iso8601,
          last_updated: Time.current.iso8601
        }
      )

      Rails.logger.info "💬 Last session recorded: #{session_id}"
    end

    # Read current conversation status
    def current_status
      read_sensor(sensor_id(:conversation, :status))
    end

    # Get active conversation count
    def active_count
      status = read_sensor(sensor_id(:conversation, :active_count))
      status&.dig("state")&.to_i || 0
    end

    # Get today's conversation count
    def today_count
      status = read_sensor(sensor_id(:conversation, :total_today))
      return 0 unless status

      # Only return count if it's for today
      date = status.dig("attributes", "date")
      return 0 unless date == Date.current.iso8601

      status.dig("state")&.to_i || 0
    end

    # Get average response time
    def avg_response_time
      status = read_sensor(sensor_id(:conversation, :response_time))
      status&.dig("state")&.to_f || 0.0
    end

    # Check if any conversation is currently active
    def active?
      active_count > 0
    end

    # Get last session info
    def last_session
      read_sensor(sensor_id(:conversation, :last_session))
    end
  end
end
