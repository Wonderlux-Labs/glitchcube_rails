# frozen_string_literal: true

class HaDataSync
  include ActiveModel::Model
  
  # Core System Health & Status
  def self.update_backend_health(status, startup_time = nil)
    # Replaces: config/application.rb:52
    # Target: input_text.backend_health_status
    call_ha_service(
      "input_text",
      "set_value", 
      "input_text.backend_health_status",
      { value: "#{status} at #{startup_time || Time.current}" }
    )
    Rails.logger.info "🏥 Backend health updated: #{status}"
  end
  
  def self.update_deployment_status(current_commit, remote_commit, update_pending)
    # Future sensor: sensor.glitchcube_deployment_status  
    # Attributes: current_commit, remote_commit, needs_update
    call_ha_service(
      "sensor", 
      "set_state",
      "sensor.glitchcube_deployment_status",
      { 
        state: update_pending ? "update_available" : "up_to_date",
        attributes: {
          current_commit: current_commit,
          remote_commit: remote_commit,
          needs_update: update_pending
        }
      }
    )
    Rails.logger.info "🚀 Deployment status updated"
  end
  
  # Conversation & Memory System
  def self.update_conversation_status(session_id, status, message_count, tools_used = [])
    # New sensor: sensor.glitchcube_conversation_status
    # Attributes: session_id, message_count, tools_used, last_updated
    call_ha_service(
      "sensor",
      "set_state",
      "sensor.glitchcube_conversation_status",
      {
        state: status,
        attributes: {
          session_id: session_id,
          message_count: message_count,
          tools_used: tools_used,
          last_updated: Time.current.iso8601
        }
      }
    )
    Rails.logger.info "💬 Conversation status updated: #{session_id} - #{status}"
  end
  
  def self.update_memory_stats(total_memories, recent_extractions, last_extraction_time)
    # New sensor: sensor.glitchcube_memory_stats
    # Attributes: total_count, recent_extractions, last_extraction
    call_ha_service(
      "sensor",
      "set_state", 
      "sensor.glitchcube_memory_stats",
      {
        state: total_memories,
        attributes: {
          total_count: total_memories,
          recent_extractions: recent_extractions,
          last_extraction: last_extraction_time&.iso8601
        }
      }
    )
    Rails.logger.info "🧠 Memory stats updated: #{total_memories} total"
  end
  
  # World State & Context (currently in world_state_updaters/)
  def self.update_world_state(weather_conditions, location_summary, upcoming_events)
    # Replaces: app/services/world_state_updaters/weather_forecast_summarizer_service.rb:208
    # Target: sensor.world_state
    call_ha_service(
      "sensor",
      "set_state",
      "sensor.world_state",
      {
        state: "active",
        attributes: {
          weather_conditions: weather_conditions,
          location_summary: location_summary,
          upcoming_events: upcoming_events,
          last_updated: Time.current.iso8601
        }
      }
    )
    Rails.logger.info "🌍 World state updated"
  end
  
  def self.update_glitchcube_context(time_of_day, location, weather_summary, current_needs = nil)
    # Enhances: data/homeassistant/template/glitchcube_context.yaml
    # Target: sensor.glitchcube_context
    call_ha_service(
      "sensor",
      "set_state",
      "sensor.glitchcube_context",
      {
        state: "active",
        attributes: {
          time_of_day: time_of_day,
          current_location: location,
          weather_summary: weather_summary,
          current_needs: current_needs,
          last_updated: Time.current.iso8601
        }
      }
    )
    Rails.logger.info "🎯 Context updated: #{time_of_day} at #{location}"
  end
  
  # Goals & Persona Management  
  def self.update_current_goal(goal_text, importance, deadline = nil, progress = nil)
    # Replaces: app/services/goal_service.rb:227,255
    # Target: sensor.glitchcube_current_goal
    call_ha_service(
      "sensor",
      "set_state",
      "sensor.glitchcube_current_goal", 
      {
        state: goal_text.truncate(50),
        attributes: {
          goal_text: goal_text,
          importance: importance,
          deadline: deadline&.iso8601,
          progress: progress,
          last_updated: Time.current.iso8601
        }
      }
    )
    Rails.logger.info "🎯 Goal updated: #{goal_text.truncate(50)}"
  end
  
  def self.update_persona(persona_name, capabilities = [], restrictions = [])
    # Replaces: app/models/cube_persona.rb:22
    # Target: input_select.current_persona + sensor.persona_details
    call_ha_service(
      "input_select",
      "select_option",
      "input_select.current_persona",
      { option: persona_name }
    )
    
    call_ha_service(
      "sensor",
      "set_state", 
      "sensor.persona_details",
      {
        state: persona_name,
        attributes: {
          capabilities: capabilities,
          restrictions: restrictions,
          last_updated: Time.current.iso8601
        }
      }
    )
    Rails.logger.info "🎭 Persona updated: #{persona_name}"
  end
  
  # GPS & Location (currently in gps_controller/services)
  def self.update_location(lat, lng, location_name, accuracy = nil)
    # New sensor: sensor.glitchcube_location
    # Attributes: latitude, longitude, location_name, accuracy, last_updated
    call_ha_service(
      "sensor",
      "set_state",
      "sensor.glitchcube_location",
      {
        state: location_name,
        attributes: {
          latitude: lat,
          longitude: lng,
          location_name: location_name,
          accuracy: accuracy,
          last_updated: Time.current.iso8601
        }
      }
    )
    Rails.logger.info "📍 Location updated: #{location_name}"
  end
  
  def self.update_proximity(nearby_landmarks, distance_to_landmarks = {})
    # New sensor: sensor.glitchcube_proximity
    # Attributes: nearby_landmarks, distances, closest_landmark
    closest = distance_to_landmarks.min_by { |_, distance| distance }
    
    call_ha_service(
      "sensor",
      "set_state",
      "sensor.glitchcube_proximity",
      {
        state: closest&.first || "unknown",
        attributes: {
          nearby_landmarks: nearby_landmarks,
          distances: distance_to_landmarks,
          closest_landmark: closest&.first,
          closest_distance: closest&.last,
          last_updated: Time.current.iso8601
        }
      }
    )
    Rails.logger.info "🎯 Proximity updated: #{nearby_landmarks.count} landmarks"
  end
  
  # Tool & Action Tracking
  def self.update_last_tool_execution(tool_name, success, execution_time, parameters = {})
    # New sensor: sensor.glitchcube_last_tool
    # Attributes: tool_name, success, execution_time, parameters
    call_ha_service(
      "sensor",
      "set_state",
      "sensor.glitchcube_last_tool",
      {
        state: tool_name,
        attributes: {
          tool_name: tool_name,
          success: success,
          execution_time: execution_time,
          parameters: parameters.to_json,
          timestamp: Time.current.iso8601
        }
      }
    )
    Rails.logger.info "🔧 Tool execution logged: #{tool_name} - #{success ? 'SUCCESS' : 'FAILED'}"
  end
  
  # Health & Monitoring
  def self.update_api_health(endpoint, response_time, status_code, last_success)
    # Enhances: data/homeassistant/sensors/api_health.yaml
    # Target: sensor.glitchcube_api_health
    status = status_code.to_i.between?(200, 299) ? "healthy" : "error"
    
    call_ha_service(
      "sensor",
      "set_state",
      "sensor.glitchcube_api_health",
      {
        state: status,
        attributes: {
          endpoint: endpoint,
          response_time: response_time,
          status_code: status_code,
          last_success: last_success&.iso8601,
          last_checked: Time.current.iso8601
        }
      }
    )
    Rails.logger.info "🏥 API health updated: #{endpoint} - #{status}"
  end

  # Breaking News Management (for remote announcements to cube)
  def self.update_breaking_news(message, expires_at = nil)
    # Update Home Assistant input_text sensor
    call_ha_service(
      "input_text",
      "set_value",
      "input_text.glitchcube_breaking_news",
      { value: message }
    )
    
    # If expiration is set, schedule a clear job
    if expires_at
      ClearBreakingNewsJob.set(wait_until: expires_at).perform_later
    end
    
    Rails.logger.info "📢 Breaking news updated: #{message.truncate(50)}"
  end

  def self.get_breaking_news
    # Try cache first for speed
    cached = Rails.cache.read("breaking_news")
    return cached if cached.present?
    
    # Fall back to Home Assistant
    news_sensor = HomeAssistantService.entity("input_text.glitchcube_breaking_news")
    news_sensor&.dig("state")&.strip
  end

  def self.clear_breaking_news
    call_ha_service(
      "input_text", 
      "set_value",
      "input_text.glitchcube_breaking_news",
      { value: "[]" }
    )
    Rails.logger.info "📢 Breaking news cleared"
  end

  # Summary and Context Stats
  def self.update_summary_stats(total_summaries, people_extracted, events_extracted)
    call_ha_service(
      "sensor",
      "set_state",
      "sensor.glitchcube_summary_stats", 
      {
        state: total_summaries,
        attributes: {
          total_summaries: total_summaries,
          people_extracted: people_extracted,
          events_extracted: events_extracted,
          last_updated: Time.current.iso8601
        }
      }
    )
    Rails.logger.info "📊 Summary stats updated: #{total_summaries} summaries"
  end

  private
  
  def self.call_ha_service(domain, service, entity_id, attributes = {})
    HomeAssistantService.call_service(domain, service, { entity_id: entity_id }.merge(attributes))
  rescue => e
    Rails.logger.error "HaDataSync failed for #{entity_id}: #{e.message}"
  end
end