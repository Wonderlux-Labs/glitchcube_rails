# lib/tasks/world_state.rake

namespace :world_state do
  desc "Display all world state attributes from Home Assistant sensors"
  task show_all: :environment do
    puts "🌍 GlitchCube World State Attributes"
    puts "=" * 50

    ha_service = HomeAssistantService.new

    # Define all the sensors that contribute to world state
    sensors = {
      "sensor.world_state" => "Main World State",
      "sensor.glitchcube_location_context" => "Location Context",
      "sensor.glitchcube_current_goal" => "Current Goal",
      "sensor.glitchcube_backend_health" => "Backend Health",
      "input_boolean.safety_mode" => "Safety Mode",
      "input_select.battery_level" => "Battery Level",
      "input_text.current_persona" => "Current Persona"
    }

    sensors.each do |entity_id, name|
      puts "\n#{name} (#{entity_id}):"
      puts "-" * 30

      begin
        entity = ha_service.entity(entity_id)

        if entity
          puts "  State: #{entity['state']}"
          puts "  Last Updated: #{entity['last_updated']}"

          if entity["attributes"] && entity["attributes"].any?
            puts "  Attributes:"
            entity["attributes"].each do |key, value|
              formatted_value = format_attribute_value(value)
              puts "    #{key}: #{formatted_value}"
            end
          else
            puts "  No attributes"
          end
        else
          puts "  ❌ Entity not found or unavailable"
        end

      rescue => e
        puts "  ❌ Error: #{e.message}"
      end
    end

    # Show goal system status
    puts "\n" + "=" * 50
    puts "🎯 Goal System Status"
    puts "=" * 50

    show_goal_system_status

    # Show recent summaries
    puts "\n" + "=" * 50
    puts "📊 Recent Activity Summaries"
    puts "=" * 50

    show_recent_summaries
  end

  desc "Show goal system status from Rails cache and database"
  task show_goals: :environment do
    puts "🎯 Goal System Status"
    puts "=" * 30

    show_goal_system_status
  end

  desc "Show recent conversation and goal summaries"
  task show_summaries: :environment do
    puts "📊 Recent Activity Summaries"
    puts "=" * 30

    show_recent_summaries
  end

  desc "Test Home Assistant sensor connectivity"
  task test_connectivity: :environment do
    puts "🔍 Testing Home Assistant Connectivity"
    puts "=" * 40

    ha_service = HomeAssistantService.new

    test_entities = [
      "sensor.world_state",
      "sensor.glitchcube_location_context",
      "input_boolean.safety_mode",
      "input_select.battery_level"
    ]

    test_entities.each do |entity_id|
      begin
        entity = ha_service.entity(entity_id)
        status = entity ? "✅ Connected" : "❌ Not found"
        state = entity ? entity["state"] : "N/A"
        puts "  #{entity_id}: #{status} (#{state})"
      rescue => e
        puts "  #{entity_id}: ❌ Error - #{e.message}"
      end
    end

    # Test write capability
    puts "\n🔧 Testing write capability..."
    begin
      test_time = Time.current.iso8601
      ha_service.set_entity_state(
        "sensor.glitchcube_test_sensor",
        "test_active",
        {
          friendly_name: "GlitchCube Test Sensor",
          test_timestamp: test_time,
          icon: "mdi:test-tube"
        }
      )
      puts "  ✅ Write test successful"
    rescue => e
      puts "  ❌ Write test failed: #{e.message}"
    end
  end

  desc "Update all world state sensors with current data"
  task update_all: :environment do
    puts "🔄 Updating All World State Sensors"
    puts "=" * 40

    # Update GPS location context
    puts "📍 Updating GPS location..."
    begin
      GpsSensorUpdateJob.perform_now
      puts "  ✅ GPS location updated"
    rescue => e
      puts "  ❌ GPS update failed: #{e.message}"
    end

    # Update weather if available
    puts "🌤️ Updating weather forecast..."
    begin
      WeatherForecastSummarizerJob.perform_now
      puts "  ✅ Weather updated"
    rescue => e
      puts "  ❌ Weather update failed: #{e.message}"
    end

    # Update backend health
    puts "🏥 Updating backend health..."
    begin
      WorldStateUpdaters::BackendHealthService.call
      puts "  ✅ Backend health updated"
    rescue => e
      puts "  ❌ Backend health update failed: #{e.message}"
    end

    # Update current goal if exists
    puts "🎯 Updating current goal..."
    begin
      goal_status = GoalService.current_goal_status
      if goal_status
        # Force update HA sensors with current goal
        GoalService.send(:update_home_assistant_goal_sensors,
          { id: goal_status[:goal_id], description: goal_status[:goal_description], category: goal_status[:category] },
          goal_status[:started_at],
          goal_status[:time_limit]
        )
        puts "  ✅ Current goal sensors updated"
      else
        puts "  ℹ️ No active goal to update"
      end
    rescue => e
      puts "  ❌ Goal update failed: #{e.message}"
    end

    puts "\n🎉 World state update complete!"
  end

  private

  def format_attribute_value(value)
    case value
    when String
      value.length > 50 ? "#{value.first(50)}..." : value
    when Array
      value.length > 3 ? "#{value.first(3).join(', ')}... (#{value.length} total)" : value.join(", ")
    when Hash
      "#{value.keys.join(', ')}"
    when nil
      "null"
    else
      value.to_s
    end
  end

  def show_goal_system_status
    # Current goal from Rails cache
    current_goal = GoalService.current_goal_status
    if current_goal
      puts "Current Goal: #{current_goal[:goal_description]}"
      puts "Category: #{current_goal[:category]}"
      puts "Started: #{current_goal[:started_at]}"
      puts "Time Remaining: #{format_time_remaining(current_goal[:time_remaining])}"
      puts "Expired: #{current_goal[:expired] ? '⏰ Yes' : 'No'}"
    else
      puts "Current Goal: None active"
    end

    # Safety status
    safety_active = GoalService.safety_mode_active?
    battery_critical = GoalService.battery_level_critical?
    puts "Safety Mode: #{safety_active ? '🚨 ACTIVE' : 'Inactive'}"
    puts "Battery Critical: #{battery_critical ? '🔋 YES' : 'No'}"

    # Recent completions
    recent_completions = Summary.goal_completions.limit(3)
    if recent_completions.any?
      puts "\nRecent Goal Completions:"
      recent_completions.each do |completion|
        puts "  • #{completion.summary_text} (#{completion.created_at.strftime('%m/%d %H:%M')})"
      end
    else
      puts "\nNo completed goals yet"
    end
  end

  def show_recent_summaries
    # Hourly conversation summaries
    hourly_summaries = Summary.where(summary_type: "hourly").order(created_at: :desc).limit(3)
    if hourly_summaries.any?
      puts "Recent Hourly Summaries:"
      hourly_summaries.each do |summary|
        metadata = summary.metadata_json
        puts "  • #{summary.created_at.strftime('%m/%d %H:%M')} - #{summary.summary_text.truncate(60)}"
        puts "    Mood: #{metadata['general_mood']}, Goal Progress: #{metadata['goal_progress']}"
      end
    else
      puts "No hourly summaries yet"
    end

    # Goal completions
    goal_summaries = Summary.goal_completions.limit(5)
    if goal_summaries.any?
      puts "\nRecent Goal Completions:"
      goal_summaries.each do |summary|
        metadata = summary.metadata_json
        duration = metadata["duration_seconds"]
        duration_str = duration ? "#{(duration / 60).to_i}min" : "unknown"
        puts "  • #{summary.created_at.strftime('%m/%d %H:%M')} - #{summary.summary_text} (#{duration_str})"
      end
    else
      puts "\nNo goal completions yet"
    end
  end

  def format_time_remaining(seconds)
    return "N/A" unless seconds

    if seconds <= 0
      "Expired"
    elsif seconds < 60
      "#{seconds.to_i}s"
    elsif seconds < 3600
      "#{(seconds / 60).to_i}m"
    else
      hours = (seconds / 3600).to_i
      minutes = ((seconds % 3600) / 60).to_i
      "#{hours}h #{minutes}m"
    end
  end
end
