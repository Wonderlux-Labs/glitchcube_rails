# frozen_string_literal: true

# CubeData - Centralized HomeAssistant data management system
# This will eventually replace HaDataSync with a more organized, modular approach
class CubeData
  include ActiveModel::Model

  # Core configuration
  CACHE_TTL = 5.seconds # Default cache TTL for sensor reads
  CACHE_ENABLED = Rails.env.production? || Rails.env.development?

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

  # Module loader - automatically load all CubeData modules
  def self.load_modules!
    Dir[Rails.root.join("app/models/cube_data/*.rb")].each do |file|
      require_dependency file
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
