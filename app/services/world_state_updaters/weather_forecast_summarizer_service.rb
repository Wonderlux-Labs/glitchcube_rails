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
    final = "ALERT! WEATHER BOT IN WITH ANOTHER ARR-EEE-PORT: #{summary}"
    update_world_state_sensor(final)

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
    sensors = HomeAssistantService.entities_by_domain("sensor")
    weather = sensors.select { |s| s["entity_id"].include?("playaweather") }
    weather += weather = sensors.select { |s| s["entity_id"].include?("pirateweather") }

    weather
  rescue HomeAssistantService::Error
    []
  end

  def generate_weather_summary(weather_data)
    prompt = build_weather_prompt(weather_data)
    puts prompt
    response = LlmService.generate_text(
      prompt: prompt,
      system_prompt: build_system_prompt,
      model: "google/gemini-2.5-flash",
      temperature: 1,
      max_tokens: 500
    )

    raise LlmServiceError, "Empty response from LLM" if response.blank?

    response.strip
  rescue StandardError => e
    Rails.logger.error "❌ LLM generation failed: #{e.message}"
    raise LlmServiceError, "Failed to generate weather summary: #{e.message}"
  end

  def build_system_prompt
    <<~PROMPT
      You are a surly, slightly glitchy weather bot. Give a concise report about the current weather conditions and forecast.

      Style guidelines:
      - Be brief but informative (3-4 sentences - shorten that shit)
      - Occasionally have minor "glitches" in your output (random capitalization, brief stutters)
      - Include actual useful weather information
      - Don't be mean, just... unimpressed, but you can curse all you want. After all these people are out her ON PURPOSE!
    PROMPT
  end

  def build_weather_prompt(weather_data)
    puts format_weather_sensors(weather_data[:sensors])
    <<~PROMPT
      Here's the current weather data from our sensors:
      #{format_weather_sensors(weather_data[:sensors])}
      Generate a surly, concise weather summary based on this data on weather now and upcomign weather
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

    # Categorize sensors by timeframe
    categorized_sensors = categorize_sensors_by_timeframe(sensors)

    # Build formatted output
    build_formatted_sensor_output(categorized_sensors)
  end

  def categorize_sensors_by_timeframe(sensors)
    categories = {
      today: [],
      tomorrow: [],
      second_day: [],
      other: []
    }

    sensor_patterns = {
      today: [ "_1h", "_6h", "_12h", "hourly_summary", "daily_summary" ],
      tomorrow: [ "_1d" ],
      second_day: [ "_2d" ]
    }

    sensors.each do |sensor|
      entity_id = sensor["entity_id"].to_s
      categorized = false

      sensor_patterns.each do |category, patterns|
        if patterns.any? { |pattern| entity_id.include?(pattern) }
          categories[category] << sensor
          categorized = true
          break
        end
      end

      categories[:other] << sensor unless categorized
    end

    categories
  end

  def build_formatted_sensor_output(categories)
    output_sections = []

    # Calculate day names
    today_name = Date.current.strftime("%A")
    tomorrow_name = (Date.current + 1).strftime("%A")
    second_day_name = (Date.current + 2).strftime("%A")

    # Add sections in logical order with day names
    add_section_if_present(output_sections, "Today (#{today_name})", categories[:today])
    add_section_if_present(output_sections, "Tomorrow (#{tomorrow_name})", categories[:tomorrow])
    add_section_if_present(output_sections, "#{second_day_name}", categories[:second_day])

    output_sections.join("\n\n")
  end

  def add_section_if_present(sections, title, sensors)
    return if sensors.empty?

    section_lines = [ "#{title}:" ]
    sensors.each do |sensor|
      state = sensor["state"]
      unit = sensor.dig("attributes", "unit_of_measurement").to_s
      friendly_name = sensor.dig("attributes", "friendly_name") || sensor["entity_id"]

      section_lines << "  - #{friendly_name}: #{state}#{unit}"
    end

    sections << section_lines.join("\n")
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
