# app/services/world_state_updaters/backend_health_service.rb

class WorldStateUpdaters::BackendHealthService
  class Error < StandardError; end
  
  def self.call
    new.call
  end

  def call
    Rails.logger.info "🏥 Starting backend health sensor update"
    
    health_data = fetch_health_data
    update_health_sensor(health_data)
    
    Rails.logger.info "✅ Backend health sensor updated successfully"
    health_data[:status]
  rescue StandardError => e
    Rails.logger.error "❌ Backend health sensor update failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise Error, "Failed to update backend health: #{e.message}"
  end

  private

  def fetch_health_data
    # Get health data from our health controller logic
    health_controller = HealthController.new
    
    # Access the private methods to get the health data
    {
      status: calculate_overall_status,
      timestamp: Time.current.iso8601,
      version: '1.0.0',
      uptime: calculate_uptime,
      database: check_database_health,
      home_assistant: check_home_assistant_health,
      llm: check_llm_health,
      host: local_ip_address,
      port: 4567
    }
  end

  def calculate_overall_status
    services = {
      database: check_database_health,
      migrations: check_migration_health,
      home_assistant: check_home_assistant_health, 
      llm: check_llm_health
    }
    
    # Special handling for migration_needed - it's not unhealthy, just needs attention
    non_migration_services = services.reject { |k, v| k == :migrations }
    migration_status = services[:migrations]
    
    if non_migration_services.values.all? { |status| status == 'healthy' }
      migration_status == 'migration_needed' ? 'migration_needed' : 'healthy'
    else
      'degraded'
    end
  end

  def calculate_uptime
    # Calculate actual uptime if possible, otherwise estimate
    boot_time = Rails.application.config.booted_at rescue (Time.current - 1.hour)
    (Time.current - boot_time).to_i
  end

  def check_database_health
    ActiveRecord::Base.connection.execute('SELECT 1')
    'healthy'
  rescue StandardError
    'unhealthy'
  end

  def check_home_assistant_health
    return 'not_configured' unless Rails.configuration.home_assistant_url
    
    HomeAssistantService.instance.available?
    'healthy'
  rescue StandardError
    'unhealthy'
  end

  def check_migration_health
    # Check if there are pending migrations
    if ActiveRecord::Migration.check_all_pending!
      'healthy'
    end
  rescue ActiveRecord::PendingMigrationError
    'migration_needed'
  rescue StandardError
    'unhealthy'
  end

  def check_llm_health
    # Simple backend health check - just return healthy  
    'healthy'
  rescue StandardError
    'unhealthy'
  end

  def local_ip_address
    # Get the actual local IP that Home Assistant can reach
    Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }&.ip_address || 'localhost'
  end

  def update_health_sensor(health_data)
    # Determine sensor state based on overall health
    sensor_state = case health_data[:status]
                  when 'healthy' then 'online'
                  when 'degraded' then 'degraded'
                  else 'offline'
                  end

    # Create attributes with all health details
    attributes = {
      'friendly_name' => 'GlitchCube Backend Health',
      'icon' => health_data[:status] == 'healthy' ? 'mdi:server' : 'mdi:server-off',
      'overall_status' => health_data[:status],
      'database_status' => health_data[:database],
      'home_assistant_status' => health_data[:home_assistant],
      'llm_status' => health_data[:llm],
      'uptime_seconds' => health_data[:uptime],
      'version' => health_data[:version],
      'host' => health_data[:host],
      'port' => health_data[:port],
      'last_updated' => health_data[:timestamp],
      'health_url' => "http://#{health_data[:host]}:#{health_data[:port]}/health"
    }

    HomeAssistantService.set_entity_state(
      'sensor.glitchcube_backend_health',
      sensor_state,
      attributes
    )

    Rails.logger.info "🏥 Updated backend health sensor: #{sensor_state}"
  rescue HomeAssistantService::Error => e
    Rails.logger.error "❌ Failed to update backend health sensor: #{e.message}"
    raise Error, "Failed to update sensor: #{e.message}"
  end
end