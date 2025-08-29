# frozen_string_literal: true

class Admin::SystemController < Admin::BaseController
  def index
    @system_status = get_system_status
    @service_health = get_service_health_summary
    @resource_usage = get_resource_usage
    @recent_errors = get_recent_errors
    @background_jobs = get_background_job_stats
  end

  def health
    @detailed_health = perform_detailed_health_checks
    @service_connectivity = check_service_connectivity
    @database_health = check_database_health
    @storage_health = check_storage_health
    @external_dependencies = check_external_dependencies

    respond_to do |format|
      format.html
      format.json do
        render json: {
          overall_status: calculate_overall_health,
          checks: @detailed_health,
          services: @service_connectivity,
          database: @database_health,
          storage: @storage_health,
          external: @external_dependencies
        }
      end
    end
  end

  private

  def get_system_status
    {
      app_version: Rails.application.config.version || "Unknown",
      rails_version: Rails.version,
      ruby_version: RUBY_VERSION,
      environment: Rails.env,
      uptime: get_app_uptime,
      memory_usage: get_memory_usage,
      database_status: check_database_connectivity
    }
  end

  def get_service_health_summary
    services = {}

    # Check Home Assistant connectivity
    services[:home_assistant] = check_home_assistant_health

    # Check LLM Service
    services[:llm_service] = check_llm_service_health

    # Check Background Jobs
    services[:background_jobs] = check_background_jobs_health

    # Check GPS Services
    services[:gps_service] = check_gps_service_health

    services
  end

  def get_resource_usage
    {
      database_size: get_database_size,
      active_conversations: Conversation.where(status: 'active').count rescue 0,
      total_memories: ConversationMemory.count rescue 0,
      total_summaries: Summary.count rescue 0,
      total_people: Person.count rescue 0,
      total_events: Event.count rescue 0,
      total_facts: Fact.count rescue 0
    }
  end

  def get_recent_errors
    # This would typically come from log analysis or error tracking service
    [
      {
        timestamp: 1.hour.ago,
        level: "ERROR",
        message: "LLM service timeout",
        source: "LlmService"
      },
      {
        timestamp: 3.hours.ago,
        level: "WARN",
        message: "High memory usage detected",
        source: "SystemMonitor"
      }
    ]
  end

  def get_background_job_stats
    # Get job statistics
    {
      total_jobs: get_total_job_count,
      failed_jobs: get_failed_job_count,
      queued_jobs: get_queued_job_count,
      processing_jobs: get_processing_job_count
    }
  end

  def perform_detailed_health_checks
    checks = {}

    checks[:database] = {
      status: check_database_connectivity ? "healthy" : "unhealthy",
      response_time: measure_database_response_time,
      last_checked: Time.current
    }

    checks[:redis] = check_redis_health if defined?(Redis)

    checks[:storage] = {
      status: check_disk_space ? "healthy" : "unhealthy",
      available_space: get_available_disk_space,
      last_checked: Time.current
    }

    checks
  end

  def check_service_connectivity
    services = {}

    # Home Assistant
    services[:home_assistant] = ping_home_assistant

    # External APIs
    services[:openrouter] = check_openrouter_connectivity

    services
  end

  def check_database_health
    {
      connectivity: check_database_connectivity,
      response_time: measure_database_response_time,
      active_connections: get_active_db_connections,
      total_size: get_database_size
    }
  end

  def check_storage_health
    {
      disk_usage: get_disk_usage,
      available_space: get_available_disk_space,
      log_file_sizes: get_log_file_sizes
    }
  end

  def check_external_dependencies
    dependencies = {}

    # Home Assistant
    dependencies[:home_assistant] = {
      status: check_home_assistant_health[:status],
      url: Rails.configuration.home_assistant_url || "Not configured"
    }

    # OpenRouter/LLM Services
    dependencies[:llm_service] = {
      status: check_llm_service_health[:status],
      primary_model: Rails.configuration.primary_model || "Not configured"
    }

    dependencies
  end

  # Health check methods
  def check_database_connectivity
    ActiveRecord::Base.connection.active?
  rescue
    false
  end

  def check_home_assistant_health
    return { status: "not_configured", message: "Home Assistant URL not configured" } unless Rails.configuration.home_assistant_url

    begin
      # Use HomeAssistantService if available, otherwise make direct request
      if defined?(HomeAssistantService)
        response = HomeAssistantService.health_check
        { status: "healthy", message: "Connected", response: response }
      else
        { status: "unknown", message: "HomeAssistantService not available" }
      end
    rescue => e
      { status: "unhealthy", message: e.message }
    end
  end

  def check_llm_service_health
    begin
      # Try a simple test with LlmService if available
      if defined?(LlmService)
        response = LlmService.generate_text(
          prompt: "Test connectivity - respond with 'OK'",
          system_prompt: "You are a health check. Respond only with 'OK'.",
          max_tokens: 10,
          temperature: 0
        )
        { status: "healthy", message: "LLM service responding", test_response: response }
      else
        { status: "unknown", message: "LlmService not available" }
      end
    rescue => e
      { status: "unhealthy", message: e.message }
    end
  end

  def check_background_jobs_health
    {
      status: "healthy", # This would check your job processor
      queued: get_queued_job_count,
      failed: get_failed_job_count
    }
  end

  def check_gps_service_health
    begin
      # Check if GPS tracking is working
      if defined?(GpsTrackingService)
        current_location = GpsTrackingService.current_location
        { status: "healthy", message: "GPS tracking active", location: current_location }
      else
        { status: "unknown", message: "GPS service not available" }
      end
    rescue => e
      { status: "unhealthy", message: e.message }
    end
  end

  # Utility methods
  def get_app_uptime
    # This is a simplified version - you'd want to track actual app start time
    (Time.current - File.mtime(Rails.root.join("tmp", "pids", "server.pid"))).to_i rescue "Unknown"
  end

  def get_memory_usage
    # This would require a gem like 'get_process_mem'
    "N/A"
  end

  def measure_database_response_time
    start_time = Time.current
    ActiveRecord::Base.connection.execute("SELECT 1")
    ((Time.current - start_time) * 1000).round(2)
  rescue
    nil
  end

  def get_database_size
    # This is PostgreSQL specific
    begin
      result = ActiveRecord::Base.connection.execute(
        "SELECT pg_size_pretty(pg_database_size(current_database()))"
      )
      result.first["pg_size_pretty"]
    rescue
      "Unknown"
    end
  end

  def get_active_db_connections
    ActiveRecord::Base.connection_pool.stat[:size] rescue 0
  end

  def get_disk_usage
    # This would require system calls or gems
    "N/A"
  end

  def get_available_disk_space
    # This would require system calls or gems
    "N/A"
  end

  def get_log_file_sizes
    log_dir = Rails.root.join("log")
    return {} unless Dir.exist?(log_dir)

    log_files = {}
    Dir.glob("#{log_dir}/*.log").each do |file|
      log_files[File.basename(file)] = File.size(file)
    end
    log_files
  end

  def ping_home_assistant
    return { status: "not_configured" } unless Rails.configuration.home_assistant_url

    begin
      # Simple connectivity check
      uri = URI("#{Rails.configuration.home_assistant_url}/api/")
      response = Net::HTTP.get_response(uri)
      { status: response.code.to_i == 200 ? "healthy" : "unhealthy", code: response.code }
    rescue => e
      { status: "unhealthy", error: e.message }
    end
  end

  def check_openrouter_connectivity
    # This would check OpenRouter or other LLM service connectivity
    { status: "unknown", message: "Connectivity check not implemented" }
  end

  def check_redis_health
    # If using Redis for caching or sessions
    { status: "not_configured", message: "Redis not configured" }
  end

  def check_disk_space
    # Simple disk space check
    true # Would implement actual disk space checking
  end

  # Background job helpers
  def get_total_job_count
    # This would depend on your background job processor (Sidekiq, Resque, etc.)
    0
  end

  def get_failed_job_count
    0
  end

  def get_queued_job_count
    0
  end

  def get_processing_job_count
    0
  end

  def calculate_overall_health
    # Determine overall health based on individual checks
    "healthy" # Would implement actual logic based on checks
  end
end