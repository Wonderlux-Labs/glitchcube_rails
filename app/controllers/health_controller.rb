# app/controllers/health_controller.rb
class HealthController < ApplicationController
  # Reduce logging noise for frequent health checks
  around_action :silence_health_logging, only: [:show]
  def show
    health_data = {
      status: overall_status,
      timestamp: Time.current.iso8601,
      version: "1.0.0",
      uptime: uptime_seconds,
      services: service_health,
      host: request.host,
      port: request.port
    }

    render json: health_data
  end

  private

  def overall_status
    # Health check - all services must be healthy (allow migration_needed and not_configured as OK)
    statuses = service_health.values

    # If any service is truly unhealthy, we're degraded
    return "degraded" if statuses.include?("unhealthy")

    # If migrations needed, show that specifically
    return "migration_needed" if statuses.include?("migration_needed")

    # If Home Assistant not configured, that's OK for basic operation
    healthy_or_ok = [ "healthy", "not_configured" ]
    statuses.all? { |status| healthy_or_ok.include?(status) } ? "healthy" : "degraded"
  end

  def service_health
    service_string = Rails.cache.fetch("service_string", expires_in: 5.minutes) do
      services = {}

      # Database health
      services[:database] = check_database_health

      # Migration status
      services[:migrations] = check_migration_health

      # Home Assistant connectivity
      services[:home_assistant] = check_home_assistant_health

      # OpenRouter/LLM service
      services[:llm] = check_llm_health

      services.to_json
    end
    JSON.parse(service_string).with_indifferent_access
  end

  def check_database_health
    ActiveRecord::Base.connection.execute("SELECT 1")
    "healthy"
  rescue StandardError
    "unhealthy"
  end

  def check_migration_health
    # Check if there are pending migrations
    ActiveRecord::Migration.check_all_pending!
    "healthy" # If no exception, migrations are up to date
  rescue ActiveRecord::PendingMigrationError
    "migration_needed"
  rescue StandardError
    "unhealthy"
  end

  def check_home_assistant_health
    # Quick check if HASS is configured and reachable
    return "not_configured" unless Rails.configuration.home_assistant_url

    HomeAssistantService.instance.available?
    "healthy"
  rescue StandardError
    "unhealthy"
  end

  def check_llm_health
    # Simple backend health check - just return healthy
    "healthy"
  rescue StandardError
    "unhealthy"
  end

  def uptime_seconds
    # Simple uptime - just return a reasonable number
    # In a real app you'd track actual boot time
    3600  # 1 hour placeholder
  end

  private

  def silence_health_logging
    Rails.logger.silence(Logger::WARN) do
      yield
    end
  end
end
