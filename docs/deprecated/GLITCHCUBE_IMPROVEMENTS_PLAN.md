  # GlitchCube System Improvement Plan

  ## Analysis Summary
  Based on comprehensive code review of the GlitchCube Rails application, focusing on conversation orchestration, memory integration, Home Assistant data synchronization, and route consolidation.

  ## Key Problems Identified

  ### 1. Memory System Disconnection
  - **Issue**: Rich memory system exists (`ConversationMemoryJob`, `Memory::MemoryRecallService`, `Memory::MemoryExtractionService`) but not connected to conversation flow
  - **Current State**: `PromptService:336-340` has empty breaking news instead of memory injection
  - **Impact**: Conversations lack context and continuity

  ### 2. Scattered Home Assistant Data Pushes
  - **Issue**: 13+ locations calling `HomeAssistantService.call_service` with unclear sensor names
  - **Locations Found**:
    - `config/application.rb:52` - Backend health on startup
    - `app/models/cube_persona.rb:22` - Persona updates
    - `app/services/tools/*/` - Various tool executions
    - `app/services/goal_service.rb` - Goal updates
    - `app/services/world_state_updaters/` - State updates
  - **Impact**: Hard to track what sensors exist and their purposes

  ### 3. Conversation Route Confusion
  - **Issue**: Three separate conversation endpoints serving similar purposes
  - **Routes**:
    1. `/api/v1/conversation` (ConversationController) - Primary HASS endpoint ✅
    2. `/ha/conversation` (HomeAssistantController) - Deprecated alternative ❌
    3. `/api/v1/home_assistant/conversation/process` - Unused legacy ❌
  - **Impact**: Maintenance overhead and potential routing conflicts

  ## Implementation Plan

  ### Phase 1: HaDataSync Model (Documentation + Centralization)

  Create `app/models/ha_data_sync.rb` as the single source of truth for all Home Assistant sensor updates:

  ```ruby
  class HaDataSync
    include ActiveModel::Model
    
    # Core System Health & Status
    def self.update_backend_health(status, startup_time = nil)
      # Replaces: config/application.rb:52
      # Target: input_text.backend_health_status
    end
    
    def self.update_deployment_status(current_commit, remote_commit, update_pending)
      # Future sensor: sensor.glitchcube_deployment_status  
      # Attributes: current_commit, remote_commit, needs_update
    end
    
    # Conversation & Memory System
    def self.update_conversation_status(session_id, status, message_count, tools_used = [])
      # New sensor: sensor.glitchcube_conversation_status
      # Attributes: session_id, message_count, tools_used, last_updated
    end
    
    def self.update_memory_stats(total_memories, recent_extractions, last_extraction_time)
      # New sensor: sensor.glitchcube_memory_stats
      # Attributes: total_count, recent_extractions, last_extraction
    end
    
    # World State & Context (currently in world_state_updaters/)
    def self.update_world_state(weather_conditions, location_summary, upcoming_events)
      # Replaces: app/services/world_state_updaters/weather_forecast_summarizer_service.rb:208
      # Target: sensor.world_state
    end
    
    def self.update_glitchcube_context(time_of_day, location, weather_summary, current_needs = nil)
      # Enhances: data/homeassistant/template/glitchcube_context.yaml
      # Target: sensor.glitchcube_context
    end
    
    # Goals & Persona Management  
    def self.update_current_goal(goal_text, importance, deadline = nil, progress = nil)
      # Replaces: app/services/goal_service.rb:227,255
      # Target: sensor.glitchcube_current_goal
    end
    
    def self.update_persona(persona_name, capabilities = [], restrictions = [])
      # Replaces: app/models/cube_persona.rb:22
      # Target: input_select.current_persona + sensor.persona_details
    end
    
    # GPS & Location (currently in gps_controller/services)
    def self.update_location(lat, lng, location_name, accuracy = nil)
      # New sensor: sensor.glitchcube_location
      # Attributes: latitude, longitude, location_name, accuracy, last_updated
    end
    
    def self.update_proximity(nearby_landmarks, distance_to_landmarks = {})
      # New sensor: sensor.glitchcube_proximity
      # Attributes: nearby_landmarks, distances, closest_landmark
    end
    
    # Tool & Action Tracking
    def self.update_last_tool_execution(tool_name, success, execution_time, parameters = {})
      # New sensor: sensor.glitchcube_last_tool
      # Attributes: tool_name, success, execution_time, parameters
    end
    
    # Health & Monitoring
    def self.update_api_health(endpoint, response_time, status_code, last_success)
      # Enhances: data/homeassistant/sensors/api_health.yaml
      # Target: sensor.glitchcube_api_health
    end

    private
    
    def self.call_ha_service(domain, service, entity_id, attributes = {})
      HomeAssistantService.call_service(domain, service, { entity_id: entity_id }.merge(attributes))
    rescue => e
      Rails.logger.error "HaDataSync failed for #{entity_id}: #{e.message}"
    end
  end
  ```

  ### Phase 2: Memory System Integration

  #### 2.1 Connect Memory to ConversationOrchestrator
  **File**: `app/services/conversation_orchestrator.rb`
  **Changes**:
  ```ruby
  # Around line 100, in build_prompt method:
  def build_prompt(message, context, persona)
    # Get relevant memories for context
    location = extract_location_from_context(context)
    relevant_memories = Memory::MemoryRecallService.get_relevant_memories(
      location: location, 
      context: context, 
      limit: 3
    )
    
    # Get upcoming events
    upcoming_events = Memory::MemoryRecallService.get_upcoming_events(
      location: location, 
      hours: 24
    )
    
    # Build enhanced context with memories
    memory_context = if relevant_memories.any?
      Memory::MemoryRecallService.format_for_context(relevant_memories)
    else
      ""
    end
    
    event_context = if upcoming_events.any?
      format_upcoming_events(upcoming_events)
    else
      ""
    end
    
    PromptService.new(persona, message, context).build_prompt(
      memory_context: memory_context,
      event_context: event_context
    )
  end
  ```

  #### 2.2 Fix Breaking News System - Make it Functional!
  **File**: `app/services/prompt_service.rb`
  **Changes**:
  ```ruby
  # UPDATE lines 336-340 to pull from Home Assistant sensor:
  def build_prompt(memory_context: "", event_context: "")
    # ... existing prompt building ...
    
    # Get breaking news from Home Assistant (can be updated via API)
    breaking_news = fetch_breaking_news
    if breaking_news.present?
      prompt += "\n**\nVERY IMPORTANT BREAKING NEWS YOU MUST PAY ATTENTION TO: #{breaking_news}\n**\n"
    else
      # Keep empty structure so model stays familiar with the format
      prompt += "\n**\nVERY IMPORTANT BREAKING NEWS YOU MUST PAY ATTENTION TO: []\n**\n"
    end
    
    # Add memory context if available
    if memory_context.present?
      prompt += memory_context
    end
    
    # Add event context if available  
    if event_context.present?
      prompt += "\n\nUPCOMING EVENTS TO REFERENCE:\n#{event_context}\n"
    end
    
    prompt
  end

  private

  def fetch_breaking_news
    # Pull from Home Assistant input_text sensor
    news_sensor = HomeAssistantService.cached_entity("input_text.glitchcube_breaking_news")
    return nil unless news_sensor&.dig("state").present?
    
    news_text = news_sensor["state"].strip
    # Return nil if it's the default empty state
    news_text.blank? || news_text == "[]" ? nil : news_text
  rescue => e
    Rails.logger.warn "Failed to fetch breaking news: #{e.message}"
    nil
  end
  ```

  #### 2.3 Add Breaking News API Endpoint
  **File**: `config/routes.rb`
  **New Route**:
  ```ruby
  namespace :api do
    namespace :v1 do
      # Breaking news injection endpoint
      post "breaking_news", to: "breaking_news#update"
      get "breaking_news", to: "breaking_news#show"
      delete "breaking_news", to: "breaking_news#clear"
    end
  end
  ```

  **New Controller**: `app/controllers/api/v1/breaking_news_controller.rb`
  ```ruby
  class Api::V1::BreakingNewsController < Api::V1::BaseController
    def update
      news_text = params[:message] || params[:text]
      expires_at = params[:expires_in]&.to_i&.minutes&.from_now
      
      # Update Home Assistant sensor
      HaDataSync.update_breaking_news(news_text, expires_at)
      
      # Also cache locally for quick access
      Rails.cache.write("breaking_news", news_text, expires_in: expires_at || 1.hour)
      
      render json: { 
        success: true, 
        message: news_text,
        expires_at: expires_at&.iso8601
      }
    end
    
    def show
      current_news = HaDataSync.get_breaking_news
      render json: { 
        message: current_news,
        active: current_news.present?
      }
    end
    
    def clear
      HaDataSync.clear_breaking_news
      Rails.cache.delete("breaking_news")
      
      render json: { success: true, message: "Breaking news cleared" }
    end
  end
  ```

  #### 2.4 HaDataSync Breaking News Methods
  **Add to** `app/models/ha_data_sync.rb`:
  ```ruby
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
  ```

  #### 2.5 Home Assistant Configuration
  **Add to** `data/homeassistant/configuration.yaml`:
  ```yaml
  input_text:
    glitchcube_breaking_news:
      name: GlitchCube Breaking News
      initial: "[]"
      max: 500
      icon: mdi:alert-circle
  ```

  #### 2.6 Usage Examples
  ```bash
  # Send breaking news from anywhere
  curl -X POST https://glitchcube.local/api/v1/breaking_news \
    -H "Authorization: Bearer YOUR_TOKEN" \
    -d "message=Eric is arriving at camp in 30 minutes! Get the lights ready!" \
    -d "expires_in=60"

  # Check current breaking news
  curl https://glitchcube.local/api/v1/breaking_news \
    -H "Authorization: Bearer YOUR_TOKEN"

  # Clear breaking news
  curl -X DELETE https://glitchcube.local/api/v1/breaking_news \
    -H "Authorization: Bearer YOUR_TOKEN"
  ```

  #### 2.7 Ensure Memory Extraction After Conversations
  **File**: `app/services/conversation_orchestrator.rb`
  **Changes**:
  ```ruby
  # In finalize_conversation or similar method:
  def queue_memory_extraction(conversation)
    return unless conversation&.ended_at
    
    ConversationMemoryJob.perform_later(conversation.session_id)
    Rails.logger.info "🧠 Queued memory extraction for session: #{conversation.session_id}"
  end
  ```

  ### Phase 3: Conversation Route Consolidation

  #### 3.1 Keep Primary Route
  - **Keep**: `/api/v1/conversation` (ConversationController) - Primary HASS endpoint
  - **Keep**: `/api/v1/conversation/proactive` - Proactive conversations

  #### 3.2 Deprecate Legacy Routes
  **File**: `config/routes.rb`
  **Changes**:
  ```ruby
  # REMOVE these routes (lines 21, 56):
  # post "conversation/process", to: "home_assistant#conversation_process"  
  # post "ha/conversation", to: "home_assistant#conversation_process"

  # KEEP only:
  post "conversation", to: "conversation#handle"
  post "conversation/proactive", to: "conversation#proactive"
  ```

  #### 3.3 Remove Unused Controller Method
  **File**: `app/controllers/home_assistant_controller.rb`
  **Changes**:
  ```ruby
  # REMOVE conversation_process method (lines 6-43)
  # KEEP health, entities, trigger_world_state_service methods
  ```

  ### Phase 4: Context Enhancement

  #### 4.1 Real Sensor Data Integration
  **File**: `app/services/prompt_service.rb`
  **Changes**:
  ```ruby
  def build_enhanced_context(base_context)
    enhanced = base_context.dup
    
    # Get real sensor data
    begin
      glitchcube_context = HomeAssistantService.entity("sensor.glitchcube_context")
      if glitchcube_context&.dig("state") != "unavailable"
        enhanced[:weather_summary] = glitchcube_context.dig("attributes", "weather_summary")
        enhanced[:time_of_day] = glitchcube_context.dig("attributes", "time_of_day")
        enhanced[:current_location] = glitchcube_context.dig("attributes", "current_location")
      end
      
      # Get goal context
      current_goal = HomeAssistantService.entity("sensor.glitchcube_current_goal")
      if current_goal&.dig("state") != "unavailable"
        enhanced[:current_goal] = current_goal.dig("attributes", "goal_text")
        enhanced[:goal_importance] = current_goal.dig("attributes", "importance")
      end
      
    rescue => e
      Rails.logger.warn "Failed to enhance context with sensor data: #{e.message}"
    end
    
    enhanced
  end
  ```

  ### Phase 5: Basic Caching Layer

  #### 5.1 Persona Configuration Caching
  **File**: `app/models/cube_persona.rb`
  **Changes**:
  ```ruby
  def self.cached_persona_config(persona_name)
    Rails.cache.fetch("persona_config_#{persona_name}", expires_in: 5.minutes) do
      # Existing persona loading logic
      load_persona_config(persona_name)
    end
  end
  ```

  #### 5.2 Home Assistant Entity Caching  
  **File**: `app/services/home_assistant_service.rb`
  **Changes**:
  ```ruby
  def self.cached_entities
    Rails.cache.fetch("ha_entities", expires_in: 1.minute) do
      entities
    end
  end

  def self.cached_entity(entity_id)
    Rails.cache.fetch("ha_entity_#{entity_id}", expires_in: 30.seconds) do
      entity(entity_id)
    end
  end
  ```

  #### 5.3 Memory Query Caching
  **File**: `app/services/memory/memory_recall_service.rb`
  **Changes**:
  ```ruby
  def get_relevant_memories(location: nil, context: {}, limit: 3)
    cache_key = "memories_#{location}_#{context.hash}_#{limit}"
    
    Rails.cache.fetch(cache_key, expires_in: 30.seconds) do
      # Existing memory selection logic
      select_relevant_memories(location, context, limit)
    end
  end
  ```

  ### Phase 6: Configuration & Maintenance

  #### 6.1 Keep SolidQueue Jobs for Debugging
  **File**: `config/application.rb`
  **Changes**:
  ```ruby
  # MODIFY lines 30-45 to be conditional:
  config.after_initialize do
    if defined?(SolidQueue::Job) && ENV['CLEAR_QUEUE_ON_STARTUP'] == 'true'
      # Only clear jobs if explicitly requested
      begin
        jobs_cleared = SolidQueue::Job.count
        if jobs_cleared > 0
          Rails.logger.info "🧹 Clearing #{jobs_cleared} SolidQueue jobs on startup"
          SolidQueue::Job.delete_all
        end
      rescue => e
        Rails.logger.warn "🧹 Failed to clear SolidQueue jobs: #{e.message}"
      end
    end
  end
  ```

  ## Expected Outcomes

  ### 1. Clear Sensor Documentation
  - All Home Assistant sensors documented in HaDataSync model
  - Method names clearly indicate sensor purpose and attributes
  - Centralized place to see what data is being tracked

  ### 2. Enhanced Conversation Context
  - Conversations will include relevant memories from past interactions
  - Real-time location and weather context
  - Upcoming events naturally referenced
  - No more empty breaking news disruption

  ### 3. Simplified Architecture
  - Single conversation endpoint for all Home Assistant requests
  - Reduced maintenance overhead
  - Clear separation of concerns

  ### 4. Performance Improvements  
  - Cached persona configurations reduce repeated file reads
  - Cached entity queries reduce Home Assistant API calls
  - Cached memory queries reduce database load

  ### 5. Better Debugging
  - Persistent SolidQueue jobs allow investigation of tool execution
  - Centralized logging through HaDataSync methods
  - Clear audit trail of sensor updates

  ## Migration Strategy

  1. **Week 1**: Implement HaDataSync model and migrate 3-4 core sensor updates
  2. **Week 2**: Connect memory system and remove breaking news bug
  3. **Week 3**: Consolidate conversation routes and enhance context
  4. **Week 4**: Add caching layer and finalize remaining sensor migrations

  ## Risk Assessment

  - **Low Risk**: HaDataSync model is purely additive
  - **Medium Risk**: Memory integration changes conversation flow
  - **High Risk**: Route consolidation may break Home Assistant integration

  **Mitigation**: Implement behind feature flags, test thoroughly with Home Assistant before deprecating old routes.

  ## Success Metrics

  1. **Memory Integration**: Conversations reference past interactions within 2-3 exchanges
  2. **Sensor Clarity**: All sensor updates go through documented HaDataSync methods
  3. **Route Simplification**: Only `/api/v1/conversation` endpoint in active use
  4. **Performance**: 30% reduction in database queries through caching
  5. **Context Quality**: Conversations include real-time weather/location context

  ---

  *This plan addresses the core issues identified in the comprehensive code review while maintaining system stability and improving maintainability.*