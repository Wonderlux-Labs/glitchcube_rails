# app/services/goal_service.rb

class GoalService
  class << self
    GOALS_FILE = Rails.root.join('data', 'goals.yml')
    
    # Cache keys for current goal state
    CURRENT_GOAL_KEY = 'current_goal'
    GOAL_STARTED_AT_KEY = 'current_goal_started_at'
    GOAL_TIME_LIMIT_KEY = 'current_goal_max_time_limit'
    
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
        selected_goal = select_random_goal_from_category(goals_data['safety_goals'])
        Rails.logger.info "⚠️ Safety mode active - selected safety goal: #{selected_goal}"
      else
        # Random selection from non-safety categories
        available_categories = goals_data.keys.reject { |k| k == 'safety_goals' }
        random_category = available_categories.sample
        selected_goal = select_random_goal_from_category(goals_data[random_category])
        Rails.logger.info "🎲 Selected goal from #{random_category}: #{selected_goal}"
      end
      
      return nil unless selected_goal
      
      # Store goal state in cache
      Rails.cache.write(CURRENT_GOAL_KEY, selected_goal)
      Rails.cache.write(GOAL_STARTED_AT_KEY, Time.current)
      Rails.cache.write(GOAL_TIME_LIMIT_KEY, time_limit)
      
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
        summary_type: 'goal_completion',
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
      
      true
    rescue StandardError => e
      Rails.logger.error "❌ Failed to complete goal: #{e.message}"
      false
    end
    
    # Get all completed goals
    def all_completed_goals
      Summary.where(summary_type: 'goal_completion').recent.map do |summary|
        metadata = summary.metadata_json
        {
          goal_id: metadata['goal_id'],
          goal_category: metadata['goal_category'],
          description: summary.summary_text,
          completed_at: summary.created_at,
          duration: metadata['duration_seconds'],
          completion_notes: metadata['completion_notes'],
          expired: metadata['expired']
        }
      end
    end
    
    # Check if safety mode should be active
    def safety_mode_active?
      # Check Home Assistant safety mode
      safety_mode = Rails.cache.fetch('safety_mode_status', expires_in: 1.minute) do
        ha_service = HomeAssistantService.new
        safety_entity = ha_service.entity('input_boolean.safety_mode')
        safety_entity&.dig('state') == 'on'
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
      Rails.cache.fetch('battery_level_status', expires_in: 2.minutes) do
        ha_service = HomeAssistantService.new
        battery_entity = ha_service.entity('input_select.battery_level')
        battery_level = battery_entity&.dig('state')
        
        %w[low critical].include?(battery_level&.downcase)
      end
    rescue StandardError => e
      Rails.logger.error "Failed to check battery level: #{e.message}"
      false
    end
    
    # Force goal switch (for persona agency)
    def request_new_goal(reason: 'persona_request', time_limit: 30.minutes)
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
          description: goal_data['description'],
          triggers: goal_data['triggers'] || [],
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
      'unknown'
    end
    
    def calculate_time_remaining(started_at, time_limit)
      return nil unless started_at && time_limit
      
      elapsed = Time.current - started_at
      remaining = time_limit - elapsed
      
      [remaining, 0].max # Don't return negative time
    end
    
    def clear_current_goal
      Rails.cache.delete(CURRENT_GOAL_KEY)
      Rails.cache.delete(GOAL_STARTED_AT_KEY)
      Rails.cache.delete(GOAL_TIME_LIMIT_KEY)
    end
  end
end