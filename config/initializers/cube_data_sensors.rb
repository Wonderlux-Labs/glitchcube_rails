# frozen_string_literal: true

# CubeData Sensor Registry
# Central definition of all HomeAssistant sensors used by the GlitchCube
# This provides a single source of truth for sensor names and configurations

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

  # Location & GPS
  location: {
    current: "sensor.glitchcube_location",
    context: "sensor.glitchcube_location_context",
    proximity: "sensor.glitchcube_proximity",
    latitude: "sensor.glitchcube_latitude",
    longitude: "sensor.glitchcube_longitude",
    accuracy: "sensor.glitchcube_location_accuracy"
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
    info: "sensor.cube_mode_info",
    battery: "input_select.battery_level",
    low_power: "binary_sensor.glitchcube_low_power_mode"
  },

  # Goals & Tasks
  goals: {
    current: "sensor.glitchcube_current_goal",
    completed: "sensor.glitchcube_goals_completed",
    pending: "sensor.glitchcube_goals_pending"
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

# Helper method to get sensor ID by path
# Example: CubeData.sensor_id(:system, :health) => "sensor.glitchcube_backend_health"
class CubeData
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
end
