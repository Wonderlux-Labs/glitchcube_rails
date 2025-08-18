# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def show
    health_data = {
      status: overall_status,
      timestamp: Time.current.iso8601,
      version: '1.0.0',
      uptime: uptime_seconds,
      services: service_health,
      host: request.host,
      port: request.port
    }
    
    render json: health_data
  end
  
  private
  
  def overall_status
    # Simple health check - all services must be healthy
    service_health.values.all? { |status| status == 'healthy' } ? 'healthy' : 'degraded'
  end
  
  def service_health
    services = {}
    
    # Database health
    services[:database] = check_database_health
    
    # Home Assistant connectivity
    services[:home_assistant] = check_home_assistant_health
    
    # OpenRouter/LLM service
    services[:llm] = check_llm_health
    
    services
  end
  
  def check_database_health
    ActiveRecord::Base.connection.execute('SELECT 1')
    'healthy'
  rescue StandardError
    'unhealthy'
  end
  
  def check_home_assistant_health
    # Quick check if HASS is configured and reachable
    return 'not_configured' unless Rails.configuration.home_assistant_url
    
    HomeAssistantService.instance.available?
    'healthy'
  rescue StandardError
    'unhealthy'
  end
  
  def check_llm_health
    # Check if OpenRouter/LLM service is configured
    return 'not_configured' unless LlmService.available?
    
    # Could add a quick test call here, but for now just check config
    'healthy'
  rescue StandardError
    'unhealthy'
  end
  
  def uptime_seconds
    # Simple uptime - just return a reasonable number
    # In a real app you'd track actual boot time
    3600  # 1 hour placeholder
  end
end