# app/services/goal_service.rb

class GoalService
  class << self
    GOALS_FILE = Rails.root.join("data", "goals.yml")

    # Cache keys for current goal state
    CURRENT_GOAL_KEY = "current_goal"
    GOAL_STARTED_AT_KEY = "current_goal_started_at"
    GOAL_TIME_LIMIT_KEY = "current_goal_max_time_limit"
    LAST_CATEGORY_KEY = "last_goal_category"

    # Check if safety mode is currently active
    def safety_mode_active?
      ha_service = HomeAssistantService.new

      # Check explicit safety mode toggle
      safety_mode = ha_service.entity("input_boolean.safety_mode")
      return true if safety_mode&.dig("state") == "on"

      # Check battery level for critical status
      battery_level_critical?
    rescue StandardError => e
      Rails.logger.error "Failed to check safety mode: #{e.message}"
      false
    end

    # Check if burning man quest mode is active
    def burning_man_quest_mode_active?
      ha_service = HomeAssistantService.new
      quest_mode = ha_service.entity("input_boolean.burning_man_quest_mode")
      quest_mode&.dig("state") == "on"
    rescue StandardError => e
      Rails.logger.error "Failed to check burning man quest mode: #{e.message}"
      false
    end

    # Check if battery level is critical
    def battery_level_critical?
      HaDataSync.low_power_mode?
    rescue StandardError => e
      Rails.logger.error "Failed to check battery level: #{e.message}"
      false
    end

    # Load all goals from YAML
    def load_goals
      return {} unless File.exist?(GOALS_FILE)
      YAML.load_file(GOALS_FILE) || {}
    rescue StandardError => e
      Rails.logger.error "Failed to load goals: #{e.message}"
      {}
    end

    # Select and set a new goal based on current conditions
    def select_goal(time_limit: 2.hours)
      Rails.logger.info "🎯 Selecting new goal"

      # Check if burning man quest mode is active
      if burning_man_quest_mode_active?
        return select_burning_man_quest
      end

      goals_data = load_goals
      return nil if goals_data.empty?

      # Get last category to avoid repeating
      last_category = Rails.cache.read(LAST_CATEGORY_KEY)

      # Determine which categories are appropriate based on safety mode
      if safety_mode_active?
        # In safety mode, prioritize safety goals
        available_categories = goals_data.keys.select { |key| key.include?("safety") }
        available_categories = goals_data.keys if available_categories.empty? # Fallback
      else
        # Normal mode - prefer non-safety goals
        available_categories = goals_data.keys.reject { |key| key.include?("safety") }
        available_categories = goals_data.keys if available_categories.empty? # Fallback
      end

      # Exclude the last category used if we have multiple options
      available_categories = available_categories.reject { |cat| cat == last_category } if last_category && available_categories.size > 1

      # Select random category from available ones
      selected_category = available_categories.sample
      selected_goal = select_random_goal_from_category(goals_data[selected_category], selected_category)

      Rails.logger.info "🎲 Selected goal from #{selected_category}: #{selected_goal}"

      return nil unless selected_goal

      # Store goal state in cache
      Rails.cache.write(CURRENT_GOAL_KEY, selected_goal)
      Rails.cache.write(GOAL_STARTED_AT_KEY, Time.current)
      Rails.cache.write(GOAL_TIME_LIMIT_KEY, time_limit)
      Rails.cache.write(LAST_CATEGORY_KEY, selected_category)

      # Update Home Assistant sensors
      update_home_assistant_goal_sensors(selected_goal, Time.current, time_limit)

      selected_goal
    end

    # Get current goal status
    def current_goal_status
      goal = Rails.cache.read(CURRENT_GOAL_KEY)
      return nil unless goal

      started_at = Rails.cache.read(GOAL_STARTED_AT_KEY)
      time_limit = Rails.cache.read(GOAL_TIME_LIMIT_KEY) || 2.hours

      {
        goal_id: goal[:id],
        goal_description: goal[:description],
        category: goal[:category],
        started_at: started_at,
        time_limit: time_limit,
        time_remaining: calculate_time_remaining(started_at, time_limit),
        expired: goal_expired?
      }
    end

    # Check if current goal has expired
    def goal_expired?
      started_at = Rails.cache.read(GOAL_STARTED_AT_KEY)
      time_limit = Rails.cache.read(GOAL_TIME_LIMIT_KEY)

      return false unless started_at && time_limit

      Time.current > (started_at + time_limit)
    end

    # Complete current goal and store in Summary
    def complete_goal(completion_notes: nil)
      goal_status = current_goal_status
      return false unless goal_status

      duration = Time.current - goal_status[:started_at]

      Rails.logger.info "✅ Completing goal: #{goal_status[:goal_description]}"

      # Store completion in Summary model
      Summary.create!(
        summary_type: "goal_completion",
        summary_text: "Completed goal: #{goal_status[:goal_description]}",
        start_time: goal_status[:started_at],
        end_time: Time.current,
        message_count: 1, # Required field, set to 1 for goal completions
        metadata: {
          goal_id: goal_status[:goal_id],
          goal_category: goal_status[:category],
          duration_seconds: duration.to_i,
          completion_notes: completion_notes,
          expired: goal_status[:expired]
        }.to_json
      )

      # Clear current goal from cache
      clear_current_goal

      # Update Home Assistant sensors
      clear_home_assistant_goal_sensors

      true
    rescue StandardError => e
      Rails.logger.error "❌ Failed to complete goal: #{e.message}"
      false
    end

    # Get all completed goals
    def all_completed_goals
      Summary.where(summary_type: "goal_completion").recent.map do |summary|
        metadata = summary.metadata_json
        {
          goal_id: metadata["goal_id"],
          goal_category: metadata["goal_category"],
          description: summary.summary_text,
          completed_at: summary.created_at,
          duration: metadata["duration_seconds"],
          completion_notes: metadata["completion_notes"],
          expired: metadata["expired"]
        }
      end
    end

    # Force goal switch (for persona agency)
    def request_new_goal(reason: "persona_request", time_limit: 2.hours)
      Rails.logger.info "🔄 Goal switch requested: #{reason}"

      # Complete current goal first if it exists
      if current_goal_status
        complete_goal(completion_notes: "Switched due to: #{reason}")
      end

      # Select new goal
      select_goal(time_limit: time_limit)
    end

    private

    def select_random_goal_from_category(category_goals, category_name)
      return nil unless category_goals && category_goals.any?

      # Convert to array of goal objects with metadata
      goals_array = category_goals.map do |goal_id, goal_data|
        # Handle both string format and object format
        description = goal_data.is_a?(String) ? goal_data : goal_data["description"]

        {
          id: goal_id,
          description: description,
          category: category_name
        }
      end

      goals_array.sample
    end

    def calculate_time_remaining(started_at, time_limit)
      return nil unless started_at && time_limit

      elapsed = Time.current - started_at
      remaining = time_limit - elapsed

      [ remaining, 0 ].max # Don't return negative time
    end

    def clear_current_goal
      Rails.cache.delete(CURRENT_GOAL_KEY)
      Rails.cache.delete(GOAL_STARTED_AT_KEY)
      Rails.cache.delete(GOAL_TIME_LIMIT_KEY)
      # Note: We keep LAST_CATEGORY_KEY to prevent repeating categories
    end

    # Update Home Assistant sensors with goal state
    def update_home_assistant_goal_sensors(goal, started_at, time_limit)
      ha_service = HomeAssistantService.new

      # Update current goal sensor
      ha_service.set_entity_state(
        "sensor.glitchcube_current_goal",
        goal[:description],
        {
          friendly_name: "GlitchCube Current Goal",
          icon: "mdi:target",
          goal_id: goal[:id],
          goal_category: goal[:category],
          started_at: started_at.iso8601,
          time_limit_minutes: (time_limit / 60).to_i,
          expires_at: (started_at + time_limit).iso8601,
          last_updated: Time.current.iso8601
        }
      )

      # Update world state sensor with goal info
      update_world_state_goal_attributes(goal, started_at, time_limit)

      Rails.logger.info "📊 Updated Home Assistant goal sensors"
    rescue StandardError => e
      Rails.logger.error "❌ Failed to update Home Assistant goal sensors: #{e.message}"
    end

    # Clear Home Assistant goal sensors when goal completes
    def clear_home_assistant_goal_sensors
      ha_service = HomeAssistantService.new

      ha_service.set_entity_state(
        "sensor.glitchcube_current_goal",
        "No active goal",
        {
          friendly_name: "GlitchCube Current Goal",
          icon: "mdi:target-variant",
          goal_id: nil,
          goal_category: nil,
          started_at: nil,
          time_limit_minutes: nil,
          expires_at: nil,
          last_updated: Time.current.iso8601
        }
      )

      # Clear goal info from world state sensor
      clear_world_state_goal_attributes

      Rails.logger.info "📊 Cleared Home Assistant goal sensors"
    rescue StandardError => e
      Rails.logger.error "❌ Failed to clear Home Assistant goal sensors: #{e.message}"
    end

    # Update world state sensor with goal information
    def update_world_state_goal_attributes(goal, started_at, time_limit)
      current_attributes = fetch_current_world_state_attributes

      new_attributes = current_attributes.merge(
        "current_goal" => goal[:description],
        "goal_category" => goal[:category],
        "goal_started_at" => started_at.iso8601,
        "goal_expires_at" => (started_at + time_limit).iso8601,
        "goal_updated_at" => Time.current.iso8601
      )

      HomeAssistantService.set_entity_state(
        "sensor.world_state",
        "active",
        new_attributes
      )
    rescue StandardError => e
      Rails.logger.error "❌ Failed to update world state goal attributes: #{e.message}"
    end

    # Clear goal attributes from world state sensor
    def clear_world_state_goal_attributes
      current_attributes = fetch_current_world_state_attributes

      new_attributes = current_attributes.merge(
        "current_goal" => nil,
        "goal_category" => nil,
        "goal_started_at" => nil,
        "goal_expires_at" => nil,
        "goal_updated_at" => Time.current.iso8601
      )

      HomeAssistantService.set_entity_state(
        "sensor.world_state",
        "active",
        new_attributes
      )
    rescue StandardError => e
      Rails.logger.error "❌ Failed to clear world state goal attributes: #{e.message}"
    end

    # Get current world state sensor attributes
    def fetch_current_world_state_attributes
      ha_service = HomeAssistantService.new
      world_state = ha_service.entity("sensor.world_state")

      if world_state&.dig("attributes")
        world_state["attributes"]
      else
        # Initialize sensor if it doesn't exist
        Rails.logger.info "📊 Initializing world_state sensor with default attributes"
        default_attributes = {
          "friendly_name" => "World State",
          "icon" => "mdi:earth",
          "last_updated" => Time.current.iso8601,
          "system_version" => Rails.application.class.module_parent_name,
          "environment" => Rails.env
        }

        # Create the sensor with default attributes
        ha_service.set_entity_state("sensor.world_state", "active", default_attributes)
        default_attributes
      end
    rescue StandardError => e
      Rails.logger.error "Failed to fetch world state attributes: #{e.message}"
      {} # Return empty hash on any error
    end

    # Select burning man quest for current persona
    def select_burning_man_quest
      Rails.logger.info "🔥 Selecting Burning Man quest"
      
      # Get current persona
      current_persona = CubePersona.current_persona
      return nil unless current_persona

      # Load persona themes to get quest data
      themes_file = Rails.root.join("config", "persona_themes.yml")
      return nil unless File.exist?(themes_file)

      themes_data = YAML.load_file(themes_file)
      persona_data = themes_data.dig("personas", current_persona)
      quest_data = persona_data&.dig("burning_man_quest")

      return nil unless quest_data

      # Check quest progress
      quest_progress = quest_data["quest_progress"] || 0
      max_progress = quest_data["max_progress"] || 1

      if quest_progress >= max_progress
        # Quest completed - persona has "retired" from their quest
        goal_description = "Quest completed! #{quest_data['do_goal']} ✅"
        Rails.logger.info "🎯 #{current_persona} quest is complete!"
      else
        # Quest in progress
        goal_description = if quest_progress == 0
          quest_data["get_to_goal"]
        else
          quest_data["do_goal"]  
        end
      end

      quest_goal = {
        id: "burning_man_quest_#{current_persona}",
        description: goal_description,
        category: "burning_man_quest",
        persona: current_persona,
        progress: quest_progress,
        max_progress: max_progress
      }

      # Set goal in cache with longer time limit (burning man is about the experience!)
      Rails.cache.write(CURRENT_GOAL_KEY, quest_goal)
      Rails.cache.write(GOAL_STARTED_AT_KEY, Time.current)
      Rails.cache.write(GOAL_TIME_LIMIT_KEY, 6.hours) # Longer quests
      Rails.cache.write(LAST_CATEGORY_KEY, "burning_man_quest")

      # Update Home Assistant
      update_home_assistant_goal_sensors(quest_goal, Time.current, 6.hours)

      Rails.logger.info "🔥 Selected Burning Man quest: #{quest_goal[:description]}"
      quest_goal
    rescue StandardError => e
      Rails.logger.error "❌ Failed to select Burning Man quest: #{e.message}"
      nil
    end

    # Update quest progress for current persona (call this when user completes quest step)
    def update_burning_man_quest_progress(increment = 1)
      Rails.logger.info "🔥 Updating Burning Man quest progress"
      
      current_persona = CubePersona.current_persona
      return false unless current_persona

      themes_file = Rails.root.join("config", "persona_themes.yml")
      return false unless File.exist?(themes_file)

      themes_data = YAML.load_file(themes_file)
      persona_data = themes_data.dig("personas", current_persona)
      return false unless persona_data

      quest_data = persona_data["burning_man_quest"]
      return false unless quest_data

      # Update progress
      current_progress = quest_data["quest_progress"] || 0
      max_progress = quest_data["max_progress"] || 1
      new_progress = [current_progress + increment, max_progress].min

      quest_data["quest_progress"] = new_progress

      # Write back to file
      File.write(themes_file, themes_data.to_yaml)

      Rails.logger.info "🎯 #{current_persona} quest progress: #{new_progress}/#{max_progress}"

      # Special handling for Buddy's retirement
      if current_persona == "buddy" && new_progress >= max_progress
        Rails.logger.info "🔥 BUDDY HAS RETIRED! Becoming Bad Buddy..."
        # You could trigger a persona switch here if needed
      end

      true
    rescue StandardError => e
      Rails.logger.error "❌ Failed to update Burning Man quest progress: #{e.message}"
      false
    end
  end
end
