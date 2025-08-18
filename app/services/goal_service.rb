# app/services/goal_service.rb

class GoalService
  class << self
    GOALS_FILE = Rails.root.join("data", "goals.yml")

    # Cache keys for current goal state
    CURRENT_GOAL_KEY = "current_goal"
    GOAL_STARTED_AT_KEY = "current_goal_started_at"
    GOAL_TIME_LIMIT_KEY = "current_goal_max_time_limit"

    # Load all goals from YAML
    def load_goals
      return {} unless File.exist?(GOALS_FILE)
      YAML.load_file(GOALS_FILE) || {}
    rescue StandardError => e
      Rails.logger.error "Failed to load goals: #{e.message}"
      {}
    end

    # Select and set a new goal based on current conditions
    def select_goal(time_limit: 30.minutes)
      Rails.logger.info "🎯 Selecting new goal"

      goals_data = load_goals
      return nil if goals_data.empty?

      # Check if we need safety goals
      if safety_mode_active?
        selected_goal = select_random_goal_from_category(goals_data["safety_goals"])
        Rails.logger.info "⚠️ Safety mode active - selected safety goal: #{selected_goal}"
      else
        # Random selection from non-safety categories
        available_categories = goals_data.keys.reject { |k| k == "safety_goals" }
        random_category = available_categories.sample
        selected_goal = select_random_goal_from_category(goals_data[random_category])
        Rails.logger.info "🎲 Selected goal from #{random_category}: #{selected_goal}"
      end

      return nil unless selected_goal

      # Store goal state in cache
      Rails.cache.write(CURRENT_GOAL_KEY, selected_goal)
      Rails.cache.write(GOAL_STARTED_AT_KEY, Time.current)
      Rails.cache.write(GOAL_TIME_LIMIT_KEY, time_limit)

      # Update Home Assistant sensors
      update_home_assistant_goal_sensors(selected_goal, Time.current, time_limit)

      selected_goal
    end

    # Get current goal status
    def current_goal_status
      goal = Rails.cache.read(CURRENT_GOAL_KEY)
      return nil unless goal

      started_at = Rails.cache.read(GOAL_STARTED_AT_KEY)
      time_limit = Rails.cache.read(GOAL_TIME_LIMIT_KEY) || 30.minutes

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

    # Check if safety mode should be active
    def safety_mode_active?
      # Check Home Assistant safety mode
      safety_mode = Rails.cache.fetch("safety_mode_status", expires_in: 1.minute) do
        ha_service = HomeAssistantService.new
        safety_entity = ha_service.entity("input_boolean.safety_mode")
        safety_entity&.dig("state") == "on"
      end

      # Check battery level
      battery_critical = battery_level_critical?

      safety_mode || battery_critical
    rescue StandardError => e
      Rails.logger.error "Failed to check safety mode: #{e.message}"
      false # Default to safe operation
    end

    # Check if battery level requires safety mode
    def battery_level_critical?
      Rails.cache.fetch("battery_level_status", expires_in: 2.minutes) do
        ha_service = HomeAssistantService.new
        battery_entity = ha_service.entity("input_select.battery_level")
        battery_level = battery_entity&.dig("state")

        %w[low critical].include?(battery_level&.downcase)
      end
    rescue StandardError => e
      Rails.logger.error "Failed to check battery level: #{e.message}"
      false
    end

    # Force goal switch (for persona agency)
    def request_new_goal(reason: "persona_request", time_limit: 30.minutes)
      Rails.logger.info "🔄 Goal switch requested: #{reason}"

      # Complete current goal first if it exists
      if current_goal_status
        complete_goal(completion_notes: "Switched due to: #{reason}")
      end

      # Select new goal
      select_goal(time_limit: time_limit)
    end

    private

    def select_random_goal_from_category(category_goals)
      return nil unless category_goals && category_goals.any?

      # Convert to array of goal objects with metadata
      goals_array = category_goals.map do |goal_id, goal_data|
        {
          id: goal_id,
          description: goal_data["description"],
          triggers: goal_data["triggers"] || [],
          category: find_category_for_goal(goal_id)
        }
      end

      goals_array.sample
    end

    def find_category_for_goal(goal_id)
      goals_data = load_goals
      goals_data.each do |category, goals|
        return category if goals.key?(goal_id)
      end
      "unknown"
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
          icon: goal[:category].include?("safety") ? "mdi:shield-alert" : "mdi:target",
          goal_id: goal[:id],
          goal_category: goal[:category],
          started_at: started_at.iso8601,
          time_limit_minutes: (time_limit / 60).to_i,
          expires_at: (started_at + time_limit).iso8601,
          safety_goal: goal[:category].include?("safety"),
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
          safety_goal: false,
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
        "safety_mode" => goal[:category].include?("safety"),
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
        "safety_mode" => false,
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
  end
end
