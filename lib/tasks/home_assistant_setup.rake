# lib/tasks/home_assistant_setup.rake

namespace :home_assistant do
  desc "Set up Home Assistant sensors for goal system"
  task setup_goal_sensors: :environment do
    puts "🏠 Setting up Home Assistant sensors for goal system..."
    
    ha_service = HomeAssistantService.new
    
    # Create safety_mode input boolean
    puts "Creating input_boolean.safety_mode..."
    begin
      ha_service.call_service(
        'input_boolean',
        'turn_off',
        { entity_id: 'input_boolean.safety_mode' }
      )
      puts "✅ input_boolean.safety_mode created/exists"
    rescue => e
      puts "❌ Failed to create input_boolean.safety_mode: #{e.message}"
      puts "💡 Please manually add this to your Home Assistant configuration:"
      puts <<~CONFIG
        input_boolean:
          safety_mode:
            name: "GlitchCube Safety Mode"
            initial: off
            icon: mdi:shield-alert
      CONFIG
    end
    
    # Create battery_level input select
    puts "\nCreating input_select.battery_level..."
    begin
      # Try to set it to excellent as a test
      ha_service.call_service(
        'input_select',
        'select_option',
        { entity_id: 'input_select.battery_level', option: 'excellent' }
      )
      puts "✅ input_select.battery_level created/exists"
    rescue => e
      puts "❌ Failed to create input_select.battery_level: #{e.message}"
      puts "💡 Please manually add this to your Home Assistant configuration:"
      puts <<~CONFIG
        input_select:
          battery_level:
            name: "GlitchCube Battery Level"
            options:
              - excellent
              - fair
              - low
              - critical
            initial: excellent
            icon: mdi:battery
      CONFIG
    end
    
    puts "\n🎯 Goal system sensor setup complete!"
    puts "You can now:"
    puts "- Toggle safety mode: input_boolean.safety_mode"
    puts "- Set battery level: input_select.battery_level"
    puts "- View current goal: sensor.glitchcube_current_goal"
    puts "- View world state: sensor.world_state"
    puts ""
    puts "To test goal selection in Rails console:"
    puts "  GoalService.select_goal"
    puts "  GoalService.current_goal_status"
    puts "  GoalService.safety_mode_active?"
    puts ""
    puts "To view all world state attributes:"
    puts "  rails world_state:show_all"
  end
  
  desc "Test goal system integration"
  task test_goals: :environment do
    puts "🧪 Testing goal system integration..."
    
    puts "\n1. Current safety status:"
    safety_active = GoalService.safety_mode_active?
    battery_critical = GoalService.battery_level_critical?
    puts "   Safety mode: #{safety_active ? 'ACTIVE' : 'inactive'}"
    puts "   Battery critical: #{battery_critical ? 'YES' : 'no'}"
    
    puts "\n2. Current goal status:"
    goal_status = GoalService.current_goal_status
    if goal_status
      puts "   Goal: #{goal_status[:goal_description]}"
      puts "   Category: #{goal_status[:category]}"
      puts "   Started: #{goal_status[:started_at]}"
      puts "   Time remaining: #{goal_status[:time_remaining]} seconds"
      puts "   Expired: #{goal_status[:expired]}"
    else
      puts "   No active goal"
    end
    
    puts "\n3. Selecting new goal..."
    new_goal = GoalService.select_goal(time_limit: 10.minutes)
    if new_goal
      puts "   Selected: #{new_goal[:description]} (#{new_goal[:category]})"
    else
      puts "   Failed to select goal"
    end
    
    puts "\n4. Recent goal completions:"
    completions = Summary.completed_goals.first(3)
    if completions.any?
      completions.each do |completion|
        puts "   - #{completion[:description]} (#{completion[:completed_at].strftime('%m/%d %H:%M')})"
      end
    else
      puts "   No completed goals yet"
    end
    
    puts "\n✅ Goal system test complete!"
  end
end