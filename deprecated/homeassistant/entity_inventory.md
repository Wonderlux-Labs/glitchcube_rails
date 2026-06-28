# Home Assistant Entity Inventory
**Total Entities: 498** | **Last Updated: 2025-08-18**

## 🔧 REQUIRED FIXES
- [ ] Switch all `input_text.current_persona` references to `input_select.current_persona`
- [ ] Fix light entity references: `light.cube_light` → `light.cube_inner`
- [ ] Fix light entity references: `light.cart_light` → `light.cube_light_top`
- [ ] Create world_state sensor with all attributes (with defaults)
- [ ] Remove duplicate template sensors

---

## 💡 LIGHTS (35 entities)

### Active/Available
- ✅ `light.cube_inner` - **Cube Light** (MAIN - referenced wrong as light.cube_light)
- ✅ `light.cube_voice_ring` - Square Voice LED Ring (RGB)
- ✅ `light.cube_light_top` - **Cube Head Lamp** (referenced wrong as light.cart_light)
- ✅ `light.awtrix_b85e20_matrix` - AWTRIX Matrix Display
- ✅ `light.awtrix_b85e20_indicator_1` - AWTRIX Indicator 1
- ✅ `light.awtrix_b85e20_indicator_2` - AWTRIX Indicator 2
- ✅ `light.awtrix_b85e20_indicator_3` - AWTRIX Indicator 3

### Segments (Cube Light)
- `light.office_bars_segment_004` through `light.office_bars_segment_015` (12 segments)
- `light.cube_light_segment_003` through `light.cube_light_segment_014` (12 segments)

### Unavailable
- ❌ `light.esp32_s3_box_3_52b3dc_screen` - boxy-wakey Screen
- ❌ `light.parrot_right` - Parrot Right
- ❌ `light.parrot_left` - Parrot Left
- ❌ `light.camera_indicator_light` - Camera Indicator

---

## 🔌 SWITCHES (31 entities)

### Power Control (TP-Link Strip)
- ✅ `switch.tp_link_power_strip` - Main Power Strip
- ✅ `switch.mac_switch` - Mac Mini Power
- ✅ `switch.speakers_switch` - Speakers
- ✅ `switch.main_lights_switch` - Main Lights
- ✅ `switch.fan_switch` - Fan
- ✅ `switch.strobe_switch` - Strobe (Aux)
- ✅ `switch.blacklight_switch` - Blacklight (Aux)

### Light Controls
- ✅ `switch.office_bars_power_switch` - Cube Light Power
- ✅ `switch.cube_light_power_switch` - Cube Head Lamp Power
- `switch.office_bars_gradient_toggle` - Gradient Toggle
- `switch.office_bars_dream_view_toggle` - Dream View Toggle

### Voice Assistant
- ✅ `switch.home_assistant_voice_09739d_mute` - Square Voice Mute
- ✅ `switch.home_assistant_voice_09739d_wake_sound` - Wake Sound

### Cloud Services
- ✅ `switch.cloud_alexa` - Alexa Integration
- ✅ `switch.cloud_google` - Google Assistant
- ✅ `switch.cloud_remote` - Remote Access

### AWTRIX
- ✅ `switch.awtrix_b85e20_transition` - Display Transition

### Unavailable
- ❌ `switch.esp32_s3_box_3_52b3dc_mute` - boxy-wakey Mute
- ❌ `switch.camera_*` - Camera controls (6 entities)
- ❌ `switch.seedling_light_socket_1` - Seedling Light

---

## 📊 SENSORS (248 entities)

### Health & Status
- ✅ `sensor.backend_health_check` - Rails API Health (healthy)
- `sensor.installation_health` - Installation Health Status
- `sensor.health_monitoring` - Consolidated Health
- `sensor.health_monitoring_compact` - Compact Health
- `sensor.health_monitoring_json` - JSON Health Data

### Memory & Summaries
- `sensor.recent_summaries_by_type` - Memory Summaries
- `sensor.memory_query_results` - Memory Search Results
- `sensor.recent_memories` - Recent Memory Entries

### Weather (PirateWeather)
- Multiple `sensor.pirateweather_*` entities for weather data
- `sensor.playaweather_*` - Custom Playa weather sensors

### System (Missing/Referenced)
- ❌ `sensor.wifi_signal_strength` - **MISSING BUT REFERENCED**
- ❌ `sensor.processor_temperature` - **MISSING BUT REFERENCED**
- ❌ `sensor.memory_use_percent` - **MISSING BUT REFERENCED**
- ❌ `sensor.disk_use_percent` - **MISSING BUT REFERENCED**
- ❌ `sensor.uptime` - **MISSING BUT REFERENCED**
- ❌ `sensor.local_ip` - **MISSING BUT REFERENCED**

### GPS/Location
- `sensor.cube_current_location_text` - GPS Location Text

---

## 🔘 INPUT HELPERS

### Input Select (1)
- ✅ `input_select.current_persona` - **USE THIS EVERYWHERE**
  - Options: buddy, jax, lomi, zorp, guide_mode, demo_mode, maintenance_mode, party_mode, chill_mode, explorer_mode

### Input Boolean (21)
- ✅ `input_boolean.fan_cooldown` - Fan Cooldown Timer
- ✅ `input_boolean.debug_mode` - Debug Mode
- ✅ `input_boolean.motion_detected` - Motion Detection
- ✅ `input_boolean.offline_mode` - Offline Mode
- ✅ `input_boolean.glitchcube_update_pending` - Update Available
- ✅ `input_boolean.auto_recovery_enabled` - Auto Recovery
- ✅ `input_boolean.maintenance_mode` - Maintenance Mode
- ✅ `input_boolean.trigger_restart` - Restart Trigger
- ✅ `input_boolean.low_battery` - Low Battery Status
- ✅ `input_boolean.cube_busy` - System Busy
- Plus 11 more...

### Input Text (6)
- ✅ `input_text.memory_query` - Memory Search Query
- ✅ `input_text.current_location` - Current Location
- ✅ `input_text.glitchcube_host` - Rails Backend IP
- ❌ `input_text.current_persona` - **DEPRECATED - REMOVE ALL REFERENCES**
- 3 unknown entities

### Input Number (2)
- ✅ `input_number.memory_query_limit` - Query Result Limit
- ✅ `input_number.recent_memories_limit` - Recent Memory Limit

### Input Button (1)
- ✅ `input_button.cycle_persona` - Persona Cycle Button

### Counters (2)
- ✅ `counter.daily_conversations` - Daily Conversation Count
- ✅ `counter.total_interactions` - Total Interactions

---

## 🔗 BINARY SENSORS (13 entities)

### Abstract Sensors (Created)
- ✅ `binary_sensor.low_battery` - Battery Status
- ✅ `binary_sensor.motion_detected` - Motion Sensor
- ✅ `binary_sensor.cube_busy` - System Busy
- ✅ `binary_sensor.glitchcube_update_available` - Update Available

### Missing/Referenced
- ❌ `binary_sensor.internet_connectivity` - **MISSING BUT REFERENCED**
- ❌ `binary_sensor.remote_ui` - **MISSING BUT REFERENCED**

---

## 🤖 AUTOMATIONS (21 entities)

### Active (20)
- ✅ `automation.gps_current_cube_location` - GPS Location Update
- ✅ `automation.persona_switcher` - Persona Voice Assistant Switch
- ✅ `automation.siren_auto_off` - Siren Auto-Off
- ✅ `automation.fan_auto_off` - Fan Auto-Off
- ✅ `automation.strobe_auto_off` - Strobe Auto-Off
- ✅ `automation.blacklight_auto_off` - Blacklight Auto-Off
- ✅ `automation.fan_cooldown_clear` - Fan Cooldown Clear
- ✅ `automation.health_lights_red` - Health Alert Lights
- ✅ `automation.health_healthy` - Health OK Lights
- ✅ `automation.cycle_persona_button` - Persona Cycle
- ✅ `automation.motion_auto_reset` - Motion Reset (30s)
- ✅ `automation.persona_change_flash` - Persona Change Light Flash
- ✅ `automation.low_battery_alert` - Battery Alert
- ✅ `automation.cube_busy_visual` - Busy Indicator
- ✅ `automation.awtrix_*` - AWTRIX Display Updates (5)

### Disabled (1)
- ❌ `automation.cube_light_voice` - Voice Light Feedback

---

## 🎬 SCENES (5 entities)
- `scene.installation_active` - Normal Operation
- `scene.maintenance_mode` - Maintenance
- `scene.sleep_mode` - Low Power
- `scene.demo_mode` - Demo Mode
- `scene.alert_mode` - Emergency Mode

**NOTE: All scenes reference `input_text.current_persona` - NEEDS UPDATE**

---

## 📝 SCRIPTS (4 entities)
- `script.glitchcube_tts_queued_ui` - TTS Queue
- `script.weather_forecast` - Weather Forecast
- `script.play_music_on_jukebox` - Music Player
- `script.awtrix_weather_request` - AWTRIX Weather

---

## 🎵 MEDIA PLAYERS (7 entities)
- ✅ `media_player.square_voice_media_player` - Voice Assistant Player
- ✅ `media_player.gentleonyx_local_upnp_av` - UPnP Player
- Plus 5 more (mostly idle/unavailable)

---

## 🎯 SELECT ENTITIES (15)
- ✅ `select.esp32_s3_box_3_52b3dc_assistant` - Assistant Selection (BUDDY)
- ✅ `select.home_assistant_voice_09739d_assistant` - Voice Assistant

---

## 🌤️ WEATHER (3 entities)
- ✅ `weather.pirateweather` - PirateWeather API
- ✅ `weather.playaweather` - Playa Weather
- ✅ `weather.forecast_blackrock_2` - BlackRock Forecast

---

## 🔊 OTHER ENTITIES

### Siren (1)
- ❌ `siren.small_siren` - Alert Siren (unavailable)

### Camera (1)
- ❌ `camera.camera` - Camera (unavailable)

### Voice Satellite (1)
- ✅ `assist_satellite.square_voice` - Voice Assistant Satellite

### Updates (36)
- All Home Assistant component updates (all showing "off" = up to date)

### Conversations (6)
- Various LLM conversation agents (Gemini, Mistral, etc.)

### AI Tasks (3)
- LLM task processors

---

## 📌 WORLD STATE SENSOR PROPOSAL

Create a single `sensor.world_state` with all attributes:
```yaml
sensor.world_state:
  state: "active"  # or maintenance, sleeping, etc.
  attributes:
    # Persona & Identity
    current_persona: "{{ states('input_select.current_persona') | default('buddy') }}"
    
    # Location & Environment
    current_location: "{{ states('input_text.current_location') | default('Black Rock City') }}"
    gps_latitude: "{{ state_attr('sensor.gps', 'latitude') | default(40.7682) }}"
    gps_longitude: "{{ state_attr('sensor.gps', 'longitude') | default(-119.2187) }}"
    
    # System Health
    api_health: "{{ states('sensor.backend_health_check') | default('unknown') }}"
    battery_low: "{{ states('input_boolean.low_battery') | default('off') }}"
    system_busy: "{{ states('input_boolean.cube_busy') | default('off') }}"
    
    # Environmental
    temperature: "{{ states('sensor.temperature') | default('unknown') }}"
    weather: "{{ states('weather.playaweather') | default('unknown') }}"
    motion_detected: "{{ states('input_boolean.motion_detected') | default('off') }}"
    
    # Activity
    daily_conversations: "{{ states('counter.daily_conversations') | default(0) }}"
    total_interactions: "{{ states('counter.total_interactions') | default(0) }}"
    
    # Network (with defaults for missing sensors)
    wifi_strength: "{{ states('sensor.wifi_signal_strength') | default('unknown') }}"
    internet_connected: "{{ states('binary_sensor.internet_connectivity') | default('unknown') }}"
    
    # System Resources (with defaults)
    cpu_temp: "{{ states('sensor.processor_temperature') | default('unknown') }}"
    memory_percent: "{{ states('sensor.memory_use_percent') | default('unknown') }}"
    disk_percent: "{{ states('sensor.disk_use_percent') | default('unknown') }}"
    uptime: "{{ states('sensor.uptime') | default('unknown') }}"
    
    # Timestamps
    last_updated: "{{ now().isoformat() }}"
    last_interaction: "{{ states('input_datetime.last_interaction_time') | default('never') }}"
```

This way Rails can always query `sensor.world_state` and get all context with sensible defaults!