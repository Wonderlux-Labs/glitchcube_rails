# app/services/world_state_updaters/weather_forecast_summarizer_service.rb

class WorldStateUpdaters::WeatherForecastSummarizerService
  class Error < StandardError; end
  class NoWeatherDataError < Error; end
  class LlmServiceError < Error; end

  def self.call
    new.call
  end

  def call
    Rails.logger.info "🌤️ Starting weather forecast summarization"

    weather_data = fetch_weather_data
    return handle_no_weather_data if weather_data.empty?

    summary = generate_weather_summary(weather_data)
    update_world_state_sensor(summary)

    Rails.logger.info "✅ Weather forecast summary updated successfully"
    summary
  rescue StandardError => e
    Rails.logger.error "❌ Weather forecast summarization failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise Error, "Failed to update weather forecast: #{e.message}"
  end

  private

  def fetch_weather_data
    return {} unless home_assistant_available?

    weather_entities = HomeAssistantService.entities_by_domain("weather")
    sensor_entities = fetch_weather_sensors

    {
      weather_stations: weather_entities,
      sensors: sensor_entities,
      timestamp: Time.current
    }
  rescue HomeAssistantService::Error => e
    Rails.logger.warn "⚠️ Home Assistant error fetching weather data: #{e.message}"
    {}
  end

  def fetch_weather_sensors
    weather_sensor_patterns = [
      "temperature",
      "humidity",
      "pressure",
      "weather",
      "forecast",
      "wind",
      "precipitation",
      "rain",
      "snow"
    ]

    sensors = HomeAssistantService.entities_by_domain("sensor")

    sensors.select do |sensor|
      entity_id = sensor["entity_id"].downcase
      weather_sensor_patterns.any? { |pattern| entity_id.include?(pattern) }
    end
  rescue HomeAssistantService::Error
    []
  end

  def generate_weather_summary(weather_data)
    prompt = build_weather_prompt(weather_data)

    response = LlmService.generate_text(
      prompt: prompt,
      system_prompt: build_system_prompt,
      model: "google/gemini-2.5-flash",
      temperature: 0.8,
      max_tokens: 200
    )

    raise LlmServiceError, "Empty response from LLM" if response.blank?

    response.strip
  rescue StandardError => e
    Rails.logger.error "❌ LLM generation failed: #{e.message}"
    raise LlmServiceError, "Failed to generate weather summary: #{e.message}"
  end

  def build_system_prompt
    <<~PROMPT
      You are a surly, slightly glitchy weather bot. Give a concise paragraph about current weather conditions and forecast.

      Style guidelines:
      - Be brief but informative (2-3 sentences max)
      - Use a slightly sarcastic, deadpan tone
      - Occasionally have minor "glitches" in your output (random capitalization, brief stutters)
      - Include actual useful weather information
      - Don't be mean, just... unimpressed

      Example: "Current temp is 72°F because apparently SPRING decided to show up. Humidity's sitting at 45% which is... fine, I guess. Tomorrow looks like more of the same predictable b-boring sunshine. *sigh*"
    PROMPT
  end

  def build_weather_prompt(weather_data)
    <<~PROMPT
      Here's the current weather data from our sensors:

      Weather Stations: #{weather_data[:weather_stations].length} found
      #{format_weather_stations(weather_data[:weather_stations])}

      Weather Sensors: #{weather_data[:sensors].length} found
      #{format_weather_sensors(weather_data[:sensors])}

      Generate a surly, concise weather summary based on this data.
    PROMPT
  end

  def format_weather_stations(stations)
    return "None available" if stations.empty?

    stations.map do |station|
      state = station["state"]
      attrs = station["attributes"] || {}

      "- #{station['entity_id']}: #{state}"
    end.join("\n")
  end

  def format_weather_sensors(sensors)
    return "None available" if sensors.empty?

    sensors.first(10).map do |sensor|  # Limit to first 10 to keep prompt manageable
      state = sensor["state"]
      unit = sensor.dig("attributes", "unit_of_measurement")
      friendly_name = sensor.dig("attributes", "friendly_name") || sensor["entity_id"]

      "- #{friendly_name}: #{state}#{unit}"
    end.join("\n")
  end

  def update_world_state_sensor(summary)
    world_state_entity = find_or_create_world_state_sensor

    if world_state_entity
      update_existing_sensor(world_state_entity, summary)
    else
      create_world_state_sensor(summary)
    end
  end

  def find_or_create_world_state_sensor
    # Look for existing world-state sensor
    HomeAssistantService.entity("sensor.world_state")
  rescue HomeAssistantService::Error
    nil
  end

  def update_existing_sensor(entity, summary)
    current_attributes = entity.dig("attributes") || {}

    new_attributes = current_attributes.merge(
      "weather_conditions" => summary,
      "weather_updated_at" => Time.current.iso8601
    )

    HomeAssistantService.set_entity_state(
      "sensor.world_state",
      "active",
      new_attributes
    )

    Rails.logger.info "🌤️ Updated weather_conditions on sensor.world_state"
  rescue HomeAssistantService::Error => e
    Rails.logger.error "❌ Failed to update world_state sensor: #{e.message}"
    raise Error, "Failed to update sensor: #{e.message}"
  end

  def create_world_state_sensor(summary)
    attributes = {
      "friendly_name" => "World State",
      "weather_conditions" => summary,
      "weather_updated_at" => Time.current.iso8601,
      "icon" => "mdi:earth"
    }

    HomeAssistantService.set_entity_state(
      "sensor.world_state",
      "active",
      attributes
    )

    Rails.logger.info "🌤️ Created new sensor.world_state with weather_conditions"
  rescue HomeAssistantService::Error => e
    Rails.logger.error "❌ Failed to create world_state sensor: #{e.message}"
    raise Error, "Failed to create sensor: #{e.message}"
  end

  def handle_no_weather_data
    summary = "Weather data currently unavailable. Sensors appear to be having a... moment. 🤖"
    update_world_state_sensor(summary)
    summary
  end

  def home_assistant_available?
    HomeAssistantService.available?
  rescue StandardError
    false
  end
end
