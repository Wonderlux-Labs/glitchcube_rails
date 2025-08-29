# frozen_string_literal: true

class CubeData::System < CubeData
  class << self
    # Update backend health status
    def update_health(status, startup_time = nil, additional_info = {})
      timestamp = startup_time || Time.current

      # Update main health sensor
      write_sensor(
        sensor_id(:system, :health),
        status,
        {
          startup_time: timestamp.iso8601,
          last_check: Time.current.iso8601,
          **additional_info
        }
      )

      # Also update legacy input_text for backwards compatibility
      write_sensor(
        sensor_id(:system, :health_text),
        "#{status} at #{timestamp}"
      )

      Rails.logger.info "🏥 Backend health updated: #{status}"
    end

    # Update deployment status
    def update_deployment(current_commit, remote_commit, update_pending = false)
      write_sensor(
        sensor_id(:system, :deployment),
        update_pending ? "update_available" : "up_to_date",
        {
          current_commit: current_commit,
          remote_commit: remote_commit,
          needs_update: update_pending,
          last_check: Time.current.iso8601
        }
      )

      Rails.logger.info "🚀 Deployment status updated"
    end

    # Update API health metrics
    def update_api_health(endpoint, response_time, status_code, last_success = nil)
      status = status_code.to_i.between?(200, 299) ? "healthy" : "error"

      write_sensor(
        sensor_id(:system, :api_health),
        status,
        {
          endpoint: endpoint,
          response_time: response_time,
          status_code: status_code,
          last_success: last_success&.iso8601,
          last_checked: Time.current.iso8601
        }
      )

      Rails.logger.info "🏥 API health updated: #{endpoint} - #{status}"
    end

    # Update host IP
    def update_host_ip(ip_address)
      write_sensor(sensor_id(:system, :host_ip), ip_address)
      Rails.logger.info "🌐 Host IP updated: #{ip_address}"
    end

    # Read current health status
    def health_status
      read_sensor(sensor_id(:system, :health))
    end

    # Read deployment status
    def deployment_status
      read_sensor(sensor_id(:system, :deployment))
    end

    # Check if system is healthy
    def healthy?
      status = health_status
      return false unless status

      status.dig("state") == "healthy"
    end

    # Get system uptime
    def uptime
      status = health_status
      return 0 unless status

      startup_time = status.dig("attributes", "startup_time")
      return 0 unless startup_time

      Time.current - Time.parse(startup_time)
    rescue
      0
    end
  end
end
