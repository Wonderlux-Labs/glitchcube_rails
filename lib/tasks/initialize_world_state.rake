# lib/tasks/initialize_world_state.rake

namespace :world_state do
  desc "Initialize all world state sensors in Home Assistant"
  task initialize_sensors: :environment do
    puts "🏠 Initializing World State Sensors in Home Assistant..."
    puts "=" * 50

    ha_service = HomeAssistantService.new

    # Initialize main world state sensor with all possible attributes
    puts "\n📊 Creating sensor.world_state..."
    begin
      ha_service.set_entity_state(
        "sensor.world_state",
        "active",
        {
          friendly_name: "World State",
          icon: "mdi:earth",

          # Goal attributes
          current_goal: nil,
          goal_category: nil,
          goal_started_at: nil,
          goal_expires_at: nil,
          safety_mode: false,
          goal_updated_at: Time.current.iso8601,

          # Weather attributes (will be updated by weather job)
          weather_conditions: nil,
          weather_updated_at: nil,

          # Backend health attributes (will be updated by health job)
          backend_status: nil,
          backend_updated_at: nil,

          # System info
          last_updated: Time.current.iso8601,
          system_version: Rails.application.class.module_parent_name,
          environment: Rails.env
        }
      )
      puts "  ✅ sensor.world_state created successfully"
    rescue => e
      puts "  ❌ Failed to create sensor.world_state: #{e.message}"
    end

    # Initialize current goal sensor
    puts "\n🎯 Creating sensor.glitchcube_current_goal..."
    begin
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
      puts "  ✅ sensor.glitchcube_current_goal created successfully"
    rescue => e
      puts "  ❌ Failed to create sensor.glitchcube_current_goal: #{e.message}"
    end

    # Initialize backend health sensor
    puts "\n🏥 Creating sensor.glitchcube_backend_health..."
    begin
      ha_service.set_entity_state(
        "sensor.glitchcube_backend_health",
        "unknown",
        {
          friendly_name: "GlitchCube Backend Health",
          icon: "mdi:heart-pulse",
          status: "unknown",
          cpu_usage: nil,
          memory_usage: nil,
          disk_usage: nil,
          version: Rails.application.class.module_parent_name,
          host: nil,
          port: nil,
          last_updated: Time.current.iso8601,
          health_url: nil
        }
      )
      puts "  ✅ sensor.glitchcube_backend_health created successfully"
    rescue => e
      puts "  ❌ Failed to create sensor.glitchcube_backend_health: #{e.message}"
    end

    # Create input helpers for goal system
    puts "\n🎛️ Creating input helpers..."

    # Safety mode boolean
    puts "Creating input_boolean.safety_mode..."
    begin
      # Try to turn it off to test if it exists, if not it will be created by the error handling
      ha_service.call_service("input_boolean", "turn_off", { entity_id: "input_boolean.safety_mode" })
      puts "  ✅ input_boolean.safety_mode already exists or created"
    rescue => e
      puts "  ⚠️ input_boolean.safety_mode needs manual creation in HA config:"
      puts "     Add to configuration.yaml:"
      puts "     input_boolean:"
      puts "       safety_mode:"
      puts "         name: 'GlitchCube Safety Mode'"
      puts "         initial: off"
      puts "         icon: mdi:shield-alert"
    end

    # Battery level select
    puts "Creating input_select.battery_level..."
    begin
      ha_service.call_service("input_select", "select_option", {
        entity_id: "input_select.battery_level",
        option: "excellent"
      })
      puts "  ✅ input_select.battery_level already exists or created"
    rescue => e
      puts "  ⚠️ input_select.battery_level needs manual creation in HA config:"
      puts "     Add to configuration.yaml:"
      puts "     input_select:"
      puts "       battery_level:"
      puts "         name: 'GlitchCube Battery Level'"
      puts "         options:"
      puts "           - excellent"
      puts "           - fair"
      puts "           - low"
      puts "           - critical"
      puts "         initial: excellent"
      puts "         icon: mdi:battery"
    end

    puts "\n🎉 World State Sensor Initialization Complete!"
    puts "\nNext steps:"
    puts "1. If any input helpers failed, add them to your HA configuration.yaml"
    puts "2. Restart Home Assistant if you added new config"
    puts "3. Run: rails world_state:update_all"
    puts "4. Run: rails world_state:show_all"
    puts "\nThe sensors will be automatically updated by:"
    puts "- GoalService when goals change"
    puts "- GpsSensorUpdateJob every 5 minutes"
    puts "- WeatherForecastSummarizerJob every hour"
    puts "- BackendHealthService when called"
  end

  desc "Force refresh all world state data"
  task refresh_all_data: :environment do
    puts "🔄 Refreshing All World State Data..."
    puts "=" * 40

    # Force goal system update
    if GoalService.current_goal_status
      puts "📊 Updating current goal sensors..."
      goal_status = GoalService.current_goal_status
      GoalService.send(:update_home_assistant_goal_sensors,
        {
          id: goal_status[:goal_id],
          description: goal_status[:goal_description],
          category: goal_status[:category]
        },
        goal_status[:started_at],
        goal_status[:time_limit]
      )
      puts "  ✅ Goal sensors updated"
    else
      puts "📊 Clearing goal sensors (no active goal)..."
      GoalService.send(:clear_home_assistant_goal_sensors)
      puts "  ✅ Goal sensors cleared"
    end

    # Force GPS update
    puts "📍 Updating GPS location context..."
    begin
      GpsSensorUpdateJob.perform_now
      puts "  ✅ GPS updated"
    rescue => e
      puts "  ❌ GPS update failed: #{e.message}"
    end

    # Force weather update
    puts "🌤️ Updating weather conditions..."
    begin
      WeatherForecastSummarizerJob.perform_now
      puts "  ✅ Weather updated"
    rescue => e
      puts "  ❌ Weather update failed: #{e.message}"
    end

    # Force backend health update
    puts "🏥 Updating backend health..."
    begin
      WorldStateUpdaters::BackendHealthService.call
      puts "  ✅ Backend health updated"
    rescue => e
      puts "  ❌ Backend health update failed: #{e.message}"
    end

    puts "\n✅ All world state data refreshed!"
    puts "Run 'rails world_state:show_all' to view updated state"
  end
end
