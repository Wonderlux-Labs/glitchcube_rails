# HA Sync Reference

## Rails → Home Assistant Data Sync

### Backend Health & Status
- `HaDataSync.update_backend_health(status, startup_time)` 
  - → `input_text.backend_health_status`
  - Template sensor: `sensor.backend_health_status`

- `HaDataSync.update_deployment_status(current_commit, remote_commit, update_pending)`
  - → `sensor.glitchcube_deployment_status`

### Conversation & Memory System
- `HaDataSync.update_conversation_status(session_id, status, message_count, tools_used)`
  - → `sensor.glitchcube_conversation_status`

- `HaDataSync.update_memory_stats(total_memories, recent_extractions, last_extraction_time)`
  - → `sensor.glitchcube_memory_stats`

### World State & Context
- `HaDataSync.update_world_state(weather_conditions, location_summary, upcoming_events)`
  - → `sensor.world_state`

- `HaDataSync.update_glitchcube_context(time_of_day, location, weather_summary, current_needs)`
  - → `sensor.glitchcube_context`

### Goals & Persona Management
- `HaDataSync.update_current_goal(goal_text, importance, deadline, progress)`
  - → `sensor.glitchcube_current_goal`

- `HaDataSync.update_persona(persona_name, capabilities, restrictions)`
  - → `input_select.current_persona` + `sensor.persona_details`

### GPS & Location
- `HaDataSync.update_location(lat, lng, location_name, accuracy)`
  - → `sensor.glitchcube_location`

- `HaDataSync.update_proximity(nearby_landmarks, distance_to_landmarks)`
  - → `sensor.glitchcube_proximity`

### Tool & Action Tracking
- `HaDataSync.update_last_tool_execution(tool_name, success, execution_time, parameters)`
  - → `sensor.glitchcube_last_tool`

### Health & Monitoring
- `HaDataSync.update_api_health(endpoint, response_time, status_code, last_success)`
  - → `sensor.glitchcube_api_health`

### Breaking News Management
- `HaDataSync.update_breaking_news(message, expires_at)`
  - → `input_text.glitchcube_breaking_news`
  - Template sensor: `sensor.glitchcube_breaking_news`

- `HaDataSync.get_breaking_news()`
  - ← `input_text.glitchcube_breaking_news`

- `HaDataSync.clear_breaking_news()`
  - → `input_text.glitchcube_breaking_news` = "[]"

### Summary Stats
- `HaDataSync.update_summary_stats(total_summaries, people_extracted, events_extracted)`
  - → `sensor.glitchcube_summary_stats`

### Mode Management
- `HaDataSync.update_cube_mode(mode, trigger_source)`
  - → `input_select.cube_mode`
  - → `sensor.cube_mode_info` (with metadata)

- `HaDataSync.get_current_mode()`
  - ← `input_select.cube_mode`

- `HaDataSync.low_power_mode?()`
  - Returns true if current mode is "low_power"

- `HaDataSync.enter_low_power_mode(trigger_source)`
  - → `input_select.cube_mode` = "low_power"

- `HaDataSync.exit_low_power_mode(trigger_source)`
  - → `input_select.cube_mode` = "conversation"

## Home Assistant → Rails Data Sources

### Memory Queries (REST sensors)
- `sensor.recent_summaries_by_type` 
  - ← `GET /api/v1/summaries/recent?limit=3`

- `sensor.memory_query_results`
  - ← `GET /api/v1/memories/search?q=<query>&limit=<limit>`
  - Query from: `input_text.memory_query`
  - Limit from: `input_number.memory_query_limit`

- `sensor.recent_memories`
  - ← `GET /api/v1/memories/recent?limit=<limit>`
  - Limit from: `input_number.recent_memories_limit`

## Config Entities

### Input Text
- `input_text.memory_query` - "burning man"
- `input_text.current_location` - "Black Rock City" 
- `input_text.glitchcube_host` - "192.168.0.56"
- `input_text.backend_health_status` - Rails managed
- `input_text.glitchcube_breaking_news` - Rails managed

### Input Boolean
- `input_boolean.low_battery` - System battery status
- `input_boolean.low_battery_mode` - Battery automation target
- `input_boolean.cube_busy` - System busy indicator
- `input_boolean.motion_detected` - Motion sensor
- `input_boolean.debug_mode` - Debug toggle

### Input Select
- `input_select.current_persona` - buddy|jax|zorp|thecube|neon|sparkle|crash|mobius
- `input_select.cube_mode` - conversation|jukebox|performance|guide|party|ambient|low_power

### Input Number
- `input_number.memory_query_limit` - Default: 10
- `input_number.recent_memories_limit` - Default: 10

### Counters
- `counter.daily_conversations` - Rails increments
- `counter.total_interactions` - Rails increments

## Physical Device Entities (Currently Offline)

### GPS Tracker (`heltec_htit_tracker_*`)
- 15 entities: lat/lng, speed, course, altitude, satellites, etc.

### Voice Box (`esp32_s3_box_3_52b3dc_*`) 
- 15 entities: wake word, presence, temp, humidity, battery, etc.

### Camera (`camera_*`)
- 8 entities: recording, privacy, motion detection, etc.

### Other Hardware
- `siren.small_siren` - Physical siren
- Various switches: fan, strobe, blacklight, etc.
- Lights: cube_light_top, cube_voice_ring, etc.

## Working Automations

### Voice System
- `automation.cube_voice_scene_creator_2` - Save light state on voice start
- `automation.cube_voice_listening_2` - Green lights during listening  
- `automation.cube_voice_processing_2` - Blue lights during processing
- `automation.cube_voice_speaking` - Voice ring effects
- `automation.cube_voice_speaking_and_restore` - Restore lights after

### Persona Management
- `automation.persona_switcher` - Update voice assistant settings
- `automation.cycle_persona_button` - GLITCH theme on persona change
- `automation.persona_change_flash` - Flash lights on persona change

### Auto-Off Timers
- `automation.siren_go_back_off` - 20s
- `automation.fan_auto_off` - 1min + cooldown
- `automation.strobe_auto_off` - 30s  
- `automation.blacklight_auto_off` - 30s

### Health Monitoring
- `automation.health_lights_red` - Red lights on backend down
- `automation.health_healthy` - Green celebration on backend up

### AWTRIX Display (Some disabled)
- `automation.awtrix_now_playing` - Show music info
- Various persona/battery/health displays

## Cube Operating Modes

### Mode Definitions
- **`conversation`** - Normal chat mode (default)
- **`jukebox`** - Music-focused, auto-switches to Jax persona
- **`performance`** - Extended monologues and performance mode
- **`guide`** - Location-aware tour guide for zones
- **`party`** - High energy, effects-heavy mode
- **`ambient`** - Minimal interaction, mood lighting
- **`low_power`** - Battery conservation mode, minimal lighting and processing

### Mode Usage Examples

```ruby
# From Rails controllers/services:
HaDataSync.update_cube_mode("jukebox", "user_request")

# From performance service:
HaDataSync.update_cube_mode("performance", "performance_started")
# ... do performance ...
HaDataSync.update_cube_mode("conversation", "performance_ended")

# Check current mode in any service:
current_mode = HaDataSync.get_current_mode()
# or directly:
current_mode = HomeAssistantService.entity_state("input_select.cube_mode")

# Power management:
if HaDataSync.low_power_mode?
  # Limit processing, reduce light effects, etc.
end

# Enter/exit low power mode:
HaDataSync.enter_low_power_mode("battery_low")
HaDataSync.exit_low_power_mode("battery_restored")
```

### HA Automation Examples

```yaml
# From HA automations:
service: input_select.select_option
data:
  entity_id: input_select.cube_mode
  option: performance

# Mode-based automation trigger:
trigger:
  - platform: state
    entity_id: input_select.cube_mode
    to: "jukebox"
action:
  - service: input_select.select_option
    data:
      entity_id: input_select.current_persona
      option: "jax"

# Low power mode automation:
trigger:
  - platform: state
    entity_id: input_select.cube_mode
    to: "low_power"
action:
  # Turn off most lights, reduce brightness, etc.
  - service: light.turn_off
    target:
      entity_id:
        - light.cube_light_top
        - light.strobe
        - light.blacklight
  - service: light.turn_on
    target:
      entity_id: light.cube_voice_ring
    data:
      brightness: 30
      color_name: "red"
```