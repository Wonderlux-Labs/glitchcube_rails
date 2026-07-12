# frozen_string_literal: true

# CubeData - Centralized HomeAssistant data management system
# This will eventually replace HaDataSync with a more organized, modular approach
class CubeData
  include ActiveModel::Model

  # CubeData Sensor Registry
  # Central definition of all HomeAssistant sensors used by the GlitchCube.
  # This provides a single source of truth for sensor names and configurations.
  CUBE_SENSORS = {
    # System & Health Monitoring
    system: {
      health: "sensor.glitchcube_backend_health",
      deployment: "sensor.glitchcube_deployment_status",
      api_health: "sensor.glitchcube_api_health",
      health_text: "input_text.backend_health_status", # Legacy, to be migrated
      host_ip: "input_text.glitchcube_host",
      uptime: "sensor.glitchcube_uptime",
      last_restart: "sensor.glitchcube_last_restart"
    },

    # Conversation Management
    conversation: {
      status: "sensor.glitchcube_conversation_status",
      active_count: "sensor.glitchcube_active_conversations",
      last_session: "sensor.glitchcube_last_session",
      total_today: "sensor.glitchcube_conversations_today",
      response_time: "sensor.glitchcube_avg_response_time"
    },

    # Memory & Knowledge
    memory: {
      stats: "sensor.glitchcube_memory_stats",
      last_extraction: "sensor.glitchcube_last_memory_extraction",
      total_memories: "sensor.glitchcube_total_memories",
      recent_memories: "sensor.glitchcube_recent_memories"
    },

    # Summaries & Context
    summary: {
      stats: "sensor.glitchcube_summary_stats",
      last_daily: "sensor.glitchcube_last_daily_summary",
      last_conversation: "sensor.glitchcube_last_conversation_summary"
    },

    # World State & Context
    world: {
      state: "sensor.world_state", # Main world state sensor
      context: "sensor.glitchcube_context",
      weather: "sensor.glitchcube_weather_summary",
      time_context: "sensor.glitchcube_time_context"
    },

    # Persona & Mode Management
    persona: {
      current: "input_select.current_persona",
      details: "sensor.persona_details",
      last_switch: "sensor.glitchcube_last_persona_switch",
      capabilities: "sensor.glitchcube_persona_capabilities"
    },

    # Cube Modes
    mode: {
      current: "input_select.cube_mode",
      info: "sensor.cube_mode_info"
    },

    # Tool Execution Tracking
    tools: {
      last_execution: "sensor.glitchcube_last_tool",
      execution_stats: "sensor.glitchcube_tool_stats",
      failures: "sensor.glitchcube_tool_failures"
    },

    # Events & Notifications
    events: {
      breaking_news: "input_text.glitchcube_breaking_news",
      last_event: "sensor.glitchcube_last_event",
      upcoming: "sensor.glitchcube_upcoming_events"
    },

    # Lights (for standardized control)
    lights: {
      top: "light.cube_light_top",
      inner: "light.cube_inner",
      all: "light.cube_lights"
    },

    # Performance & Monitoring
    performance: {
      mode: "binary_sensor.performance_mode",
      metrics: "sensor.glitchcube_performance_metrics",
      response_queue: "sensor.glitchcube_response_queue"
    }
  }.freeze

  # Core configuration
  CACHE_TTL = 5.seconds # Default cache TTL for sensor reads
  CACHE_ENABLED = Rails.env.production? || Rails.env.development?

  # Sensor registry helpers
  # Example: CubeData.sensor_id(:system, :health) => "sensor.glitchcube_backend_health"
  def self.sensor_id(category, sensor)
    CUBE_SENSORS.dig(category, sensor) || raise("Unknown sensor: #{category}.#{sensor}")
  end

  def self.sensor_exists?(category, sensor)
    CUBE_SENSORS.dig(category, sensor).present?
  end

  def self.all_sensors
    CUBE_SENSORS.values.map(&:values).flatten
  end

  def self.sensors_by_category(category)
    CUBE_SENSORS[category] || {}
  end

  class << self
    # Get the HomeAssistant service instance
    def ha_service
      @ha_service ||= HomeAssistantService.instance
    end

    # Central method for reading any sensor with caching
    def read_sensor(sensor_id, cache_ttl: CACHE_TTL)
      return ha_service.entity(sensor_id) unless CACHE_ENABLED

      Rails.cache.fetch("cube_data:sensor:#{sensor_id}", expires_in: cache_ttl) do
        ha_service.entity(sensor_id)
      end
    rescue => e
      Rails.logger.error "[CubeData] Failed to read sensor #{sensor_id}: #{e.message}"
      nil
    end

    # Central method for writing to any sensor (no caching)
    def write_sensor(sensor_id, state, attributes = {})
      Rails.cache.delete("cube_data:sensor:#{sensor_id}") if CACHE_ENABLED

      # Determine if it's a regular sensor or input_* entity
      if sensor_id.start_with?("input_text.", "input_select.", "input_number.", "input_boolean.")
        write_input_entity(sensor_id, state)
      else
        ha_service.set_entity_state(sensor_id, state, attributes)
      end

      Rails.logger.debug "[CubeData] Updated #{sensor_id}: #{state}"
      true
    rescue => e
      Rails.logger.error "[CubeData] Failed to write sensor #{sensor_id}: #{e.message}"
      false
    end

    # Call a HomeAssistant service
    def call_service(domain, service, data = {})
      ha_service.call_service(domain, service, data)
    rescue => e
      Rails.logger.error "[CubeData] Failed to call service #{domain}.#{service}: #{e.message}"
      false
    end

    # Clear all cached sensor data
    def clear_cache!
      Rails.cache.delete_matched("cube_data:sensor:*") if CACHE_ENABLED
    end

    # Check if HomeAssistant is available
    def available?
      ha_service.available?
    end

    private

    def write_input_entity(entity_id, value)
      domain = entity_id.split(".").first

      case domain
      when "input_text"
        call_service("input_text", "set_value", entity_id: entity_id, value: value.to_s)
      when "input_select"
        call_service("input_select", "select_option", entity_id: entity_id, option: value.to_s)
      when "input_number"
        call_service("input_number", "set_value", entity_id: entity_id, value: value.to_f)
      when "input_boolean"
        service = value ? "turn_on" : "turn_off"
        call_service("input_boolean", service, entity_id: entity_id)
      else
        raise "Unknown input entity type: #{domain}"
      end
    end
  end

  # Enhanced caching with different TTLs for different sensor types
  CACHE_TTLS = {
    # System sensors - can cache longer as they don't change often
    system: 30.seconds,
    mode: 10.seconds,
    persona: 30.seconds,

    # Dynamic sensors - shorter cache
    conversation: 5.seconds,
    location: 10.seconds,
    world: 15.seconds,

    # Very dynamic sensors - very short cache
    lights: 1.second,
    tools: 2.seconds,

    # Event/memory sensors - medium cache
    events: 10.seconds,
    memory: 15.seconds
  }.freeze

  # Get TTL for a sensor based on its category
  def self.cache_ttl_for_sensor(sensor_id)
    # Extract category from sensor ID pattern
    category = CACHE_TTLS.keys.find do |cat|
      CUBE_SENSORS[cat]&.values&.include?(sensor_id)
    end

    CACHE_TTLS[category] || CACHE_TTL
  end

  # Enhanced read_sensor with dynamic TTL
  def self.read_sensor(sensor_id, cache_ttl: nil)
    # Use category-specific TTL if not provided
    cache_ttl ||= cache_ttl_for_sensor(sensor_id)

    return ha_service.entity(sensor_id) unless CACHE_ENABLED

    Rails.cache.fetch("cube_data:sensor:#{sensor_id}", expires_in: cache_ttl) do
      ha_service.entity(sensor_id)
    end
  rescue => e
    Rails.logger.error "[CubeData] Failed to read sensor #{sensor_id}: #{e.message}"
    nil
  end

  # Cache warming - preload frequently accessed sensors
  def self.warm_cache!
    return unless CACHE_ENABLED

    # Pre-warm critical sensors
    critical_sensors = [
      sensor_id(:system, :health),
      sensor_id(:mode, :current),
      sensor_id(:persona, :current),
      sensor_id(:world, :state),
      sensor_id(:conversation, :status)
    ]

    critical_sensors.each do |sensor|
      read_sensor(sensor) rescue nil
    end

    Rails.logger.info "[CubeData] Cache warmed with #{critical_sensors.count} sensors"
  end

  # Cache statistics
  def self.cache_stats
    return {} unless CACHE_ENABLED

    cache_keys = Rails.cache.instance_variable_get(:@data)&.keys&.select { |k| k.to_s.start_with?("cube_data:sensor:") } || []

    {
      cached_sensors: cache_keys.count,
      cache_enabled: CACHE_ENABLED,
      default_ttl: CACHE_TTL
    }
  end

  # Health check method
  def self.health_check
    {
      homeassistant_available: available?,
      cached_sensors: cache_stats[:cached_sensors],
      modules_loaded: constants.select { |c| const_get(c).is_a?(Class) }.count - 1, # -1 for base class
      total_sensors: all_sensors.count
    }
  end

  # Module loader - reference all CubeData submodules so Zeitwerk autoloads them.
  # Submodules live in app/models/cube_data/ and are owned by Zeitwerk; we just
  # need to touch each constant to trigger autoloading.
  def self.load_modules!
    Dir[Rails.root.join("app/models/cube_data/*.rb")].each do |file|
      module_name = File.basename(file, ".rb").camelize
      const_get(module_name)
    end
    Rails.logger.info "[CubeData] Loaded #{constants.count - 1} modules"
  end

  # Initialize CubeData - called from initializer
  def self.initialize!
    load_modules!
    warm_cache! if Rails.env.production?

    Rails.logger.info "[CubeData] Initialized successfully"
  end
end
