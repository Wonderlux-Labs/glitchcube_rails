# app/controllers/admin/world_state_controller.rb

class Admin::WorldStateController < Admin::BaseController
  def index
    @world_state_sensor = get_world_state_sensor
    @weather_sensors = get_weather_sensors
    @all_sensors = get_all_sensors
    @available_services = get_available_world_state_services
  end

  def history
    # This would show historical changes to world state
    render json: { message: "History tracking not yet implemented" }
  end

  def trigger
    service_name = params[:service]

    begin
      service_class = "WorldStateUpdaters::#{service_name}".constantize
      result = service_class.call

      flash[:notice] = "✅ #{service_name} executed successfully"
      if result.is_a?(String)
        flash[:notice] += ": #{result.truncate(100)}"
      end
    rescue NameError
      flash[:error] = "❌ Service '#{service_name}' not found"
    rescue StandardError => e
      flash[:error] = "❌ Service failed: #{e.message}"
    end

    redirect_to admin_world_state_path
  end

  private

  def get_world_state_sensor
    HomeAssistantService.entity("sensor.world_state")
  rescue StandardError => e
    Rails.logger.error "Failed to get world state sensor: #{e.message}"
    nil
  end

  def get_weather_sensors
    weather_patterns = [ "temperature", "humidity", "pressure", "weather", "wind", "rain" ]
    sensors = HomeAssistantService.entities_by_domain("sensor")

    sensors.select do |sensor|
      entity_id = sensor["entity_id"].downcase
      weather_patterns.any? { |pattern| entity_id.include?(pattern) }
    end.first(10)  # Limit to first 10
  rescue StandardError => e
    Rails.logger.error "Failed to get weather sensors: #{e.message}"
    []
  end

  def get_all_sensors
    HomeAssistantService.entities_by_domain("sensor").count
  rescue StandardError
    0
  end

  def get_available_world_state_services
    # Scan for available world state services
    services = []

    service_dir = Rails.root.join("app", "services", "world_state_updaters")
    if Dir.exist?(service_dir)
      Dir.glob("#{service_dir}/*.rb").each do |file|
        filename = File.basename(file, ".rb")
        service_name = filename.camelize
        services << {
          name: service_name,
          filename: filename,
          description: extract_service_description(file)
        }
      end
    end

    services
  end

  def extract_service_description(file_path)
    # Simple description extraction from comments
    File.readlines(file_path).first(5).each do |line|
      if line.strip.start_with?("#") && !line.include?("app/services")
        return line.gsub("#", "").strip
      end
    end
    "No description available"
  rescue StandardError
    "Description unavailable"
  end
end
