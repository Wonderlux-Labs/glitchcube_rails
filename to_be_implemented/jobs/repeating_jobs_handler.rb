#  frozen_string_literal: true

require 'sidekiq/cron/job'

module Jobs
  # Unified handler for all repeating background services
  # Runs every 5 minutes and intelligently executes services based on their intervals
  class RepeatingJobsHandler < BaseJob
    sidekiq_options retry: 3, backtrace: true

    # Service registry - defines what services to run and their intervals
    SERVICES = {
      health_push: {
        class: 'Services::System::HealthPushService',
        method: 'push_health_status',
        interval: 15 * 60,  # 15 minutes in seconds
        description: 'Push health status to monitoring services'
      }
    }.freeze

    def perform
      job_start_time = Time.now.utc

      SERVICES.each do |service_name, config|
        next unless service_enabled?(service_name)
        next unless service_ready_to_run?(service_name, config[:interval])

        execute_service(service_name, config)
      end

      # Update Home Assistant sensor with last run time
      update_last_run_sensor(job_start_time)
    rescue StandardError => e
      logger.error "RepeatingJobsHandler failed: #{e.message}"
      logger.error e.backtrace.join("\n")

      # Still update the sensor even if some services failed
      begin
        update_last_run_sensor(job_start_time, error: e.message)
      rescue StandardError
        nil
      end

      raise
    end

    private

    def logger
      Services::Logging::SimpleLogger
    end

    # Check if a service is enabled (default: true)
    def service_enabled?(service_name)
      enabled = redis.get("repeating_jobs:#{service_name}:enabled")
      enabled.nil? || enabled == 'true'
    end

    # Check if enough time has passed since last run
    def service_ready_to_run?(service_name, interval)
      last_run = redis.get("repeating_jobs:#{service_name}:last_run")
      return true unless last_run

      Time.parse(last_run).utc + interval <= Time.now.utc
    rescue ArgumentError
      # Invalid timestamp, assume ready to run
      true
    end

    # Execute the service and update last run time
    def execute_service(service_name, config)
      start_time = Time.now.utc

      begin
        service_class = Object.const_get(config[:class])
        service_instance = service_class.new
        result = service_instance.public_send(config[:method])

        # Update last successful run
        redis.setex("repeating_jobs:#{service_name}:last_run", 7 * 24 * 60 * 60, start_time.iso8601) # 7 days

        duration = ((Time.now.utc - start_time) * 1000).round
        logger.info "✅ #{service_name} completed in #{duration}ms: #{result&.to_s&.slice(0, 100)}"
      rescue NameError => e
        logger.error "❌ #{service_name} service class not found: #{e.message}"
      rescue StandardError => e
        duration = ((Time.now.utc - start_time) * 1000).round
        logger.error "❌ #{service_name} failed after #{duration}ms: #{e.message}"

        # For critical services, don't update last_run so they retry sooner
        unless critical_service?(service_name)
          redis.setex("repeating_jobs:#{service_name}:last_run", 60 * 60, start_time.iso8601) # 1 hour
        end

        raise if critical_service?(service_name)
      end
    end

    # Define critical services that should halt job execution on failure
    def critical_service?(service_name)
      [:health_push].include?(service_name)
    end

    def redis
      @redis ||= GlitchCube.config.redis_connection || Redis.new(url: 'redis://localhost:6379/0')
    end

    # Update Home Assistant input_datetime with last run time for monitoring
    def update_last_run_sensor(run_time, error: nil)
      # Format datetime for input_datetime helper (YYYY-MM-DD HH:MM:SS format)
      datetime_str = run_time.strftime('%Y-%m-%d %H:%M:%S')

      ha_client = Services::Core::HomeAssistantClient.new
      ha_client.call_service('input_datetime', 'set_datetime', {
                               entity_id: 'input_datetime.last_repeating_jobs_run',
                               datetime: datetime_str
                             })

      logger.info "📊 Updated HA input_datetime: last_repeating_jobs_run = #{datetime_str}"
    rescue StandardError => e
      logger.error "❌ Failed to update HA input_datetime: #{e.message}"
    end
  end
end
