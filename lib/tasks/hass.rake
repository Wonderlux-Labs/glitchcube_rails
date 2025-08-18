# lib/tasks/hass.rake
namespace :hass do
  # Helper method to get argument from either task args or ENV flags
  def get_arg(args, key, env_key = nil)
    # Try task args first (bracket syntax)
    value = args[key] if args.respond_to?(:[])
    
    # Try ENV flags (--flag syntax)
    env_key ||= key.to_s.upcase
    value ||= ENV[env_key.to_s]
    
    value
  end
  
  # Helper method to parse entity argument
  def parse_entity_arg(args)
    get_arg(args, :entity_id, 'ENTITY') || get_arg(args, :entity_id, 'ENTITY_ID')
  end
  
  # Helper method to parse domain argument  
  def parse_domain_arg(args)
    get_arg(args, :domain, 'DOMAIN')
  end
  desc "Test connection to Home Assistant"
  task test: :environment do
    begin
      if HomeAssistantService.available?
        config = HomeAssistantService.config
        puts colorize("✅ Connected to Home Assistant!", :green)
        puts colorize("URL: #{Rails.configuration.home_assistant_url}", :blue)
        puts colorize("Version: #{config['version']}", :blue)
        puts colorize("Location: #{config['location_name']}", :blue)
      else
        puts colorize("❌ Cannot connect to Home Assistant", :red)
        puts colorize("URL: #{Rails.configuration.home_assistant_url}", :blue)
      end
    rescue HomeAssistantService::Error => e
      puts colorize("❌ Home Assistant Error: #{e.message}", :red)
    rescue StandardError => e
      puts colorize("❌ Connection Error: #{e.message}", :red)
    end
  end

  desc "List all entities or filter by domain: rails hass:entities[light] OR rails hass:entities --domain=light"
  task :entities, [:domain] => :environment do |_t, args|
    begin
      domain = parse_domain_arg(args)
      
      if domain
        # Call exact same service method as tools
        result = HomeAssistantService.entities_by_domain(domain)
        puts colorize("🏠 #{domain.capitalize} entities:", :cyan)
        puts JSON.pretty_generate(result)
      else
        # Call exact same service method as tools
        result = HomeAssistantService.entities
        puts colorize("🏠 All entities:", :cyan)
        puts JSON.pretty_generate(result)
      end
    rescue HomeAssistantService::Error => e
      puts colorize("❌ Error: #{e.message}", :red)
    end
  end

  desc "Get entity state and attributes: rails hass:entity[light.living_room] OR rails hass:entity --entity=light.living_room"
  task :entity, [:entity_id] => :environment do |_t, args|
    entity_id = parse_entity_arg(args)
    
    if entity_id.nil?
      puts colorize("❌ Please provide an entity_id: rails hass:entity[light.living_room] OR rails hass:entity --entity=light.living_room", :red)
      next
    end

    begin
      # Call exact same service method as tools
      result = HomeAssistantService.entity(entity_id)
      
      if result.nil?
        puts colorize("❌ Entity '#{entity_id}' not found", :red)
      else
        puts colorize("🔍 Entity: #{entity_id}", :cyan)
        puts JSON.pretty_generate(result)
      end
    rescue HomeAssistantService::Error => e
      puts colorize("❌ Error: #{e.message}", :red)
    end
  end

  desc "Get entity state: rails hass:get[sensor.temperature] OR rails hass:get --entity=sensor.temperature"
  task :get, [:entity_id] => :environment do |_t, args|
    entity_id = parse_entity_arg(args)
    
    if entity_id.nil?
      puts colorize("❌ Please provide an entity_id: rails hass:get --entity=sensor.temperature", :red)
      next
    end

    begin
      entity = HomeAssistantService.entity(entity_id)
      
      if entity.nil?
        puts colorize("❌ Entity '#{entity_id}' not found", :red)
      else
        puts colorize("🔍 Full entity data for #{entity_id}:", :cyan)
        puts JSON.pretty_generate(entity)
      end
    rescue HomeAssistantService::Error => e
      puts colorize("❌ Error: #{e.message}", :red)
    end
  end

  desc "Set entity state: rails hass:set[input_text.test,hello] OR ENTITY=input_text.test STATE=hello rails hass:set"
  task :set, [:entity_id, :state] => :environment do |_t, args|
    entity_id = parse_entity_arg(args)
    state = get_arg(args, :state, 'STATE')
    
    if entity_id.nil? || state.nil?
      puts colorize("❌ Please provide entity_id and state: ENTITY=input_text.test STATE=hello rails hass:set", :red)
      next
    end

    begin
      # Call exact same service method as tools
      result = HomeAssistantService.set_entity_state(entity_id, state)
      puts colorize("✅ Set #{entity_id} to '#{state}'", :green)
      puts JSON.pretty_generate(result)
    rescue HomeAssistantService::Error => e
      puts colorize("❌ Error: #{e.message}", :red)
    end
  end

  desc "Turn on entity: rails hass:turn_on[light.living_room] OR rails hass:turn_on --entity=light.living_room"
  task :turn_on, [:entity_id] => :environment do |_t, args|
    entity_id = parse_entity_arg(args)
    
    if entity_id.nil?
      puts colorize("❌ Please provide an entity_id: rails hass:turn_on --entity=light.living_room", :red)
      next
    end

    begin
      # Call exact same service method as tools
      result = HomeAssistantService.turn_on(entity_id)
      puts colorize("✅ Turned on #{entity_id}", :green)
      puts JSON.pretty_generate(result)
    rescue HomeAssistantService::Error => e
      puts colorize("❌ Error: #{e.message}", :red)
    end
  end

  desc "Turn off entity: rails hass:turn_off[light.living_room] OR rails hass:turn_off --entity=light.living_room"
  task :turn_off, [:entity_id] => :environment do |_t, args|
    entity_id = parse_entity_arg(args)
    
    if entity_id.nil?
      puts colorize("❌ Please provide an entity_id: rails hass:turn_off --entity=light.living_room", :red)
      next
    end

    begin
      # Call exact same service method as tools
      result = HomeAssistantService.turn_off(entity_id)
      puts colorize("✅ Turned off #{entity_id}", :green)
      puts JSON.pretty_generate(result)
    rescue HomeAssistantService::Error => e
      puts colorize("❌ Error: #{e.message}", :red)
    end
  end

  desc "Toggle entity: rails hass:toggle[light.living_room]"
  task :toggle, [:entity_id] => :environment do |_t, args|
    entity_id = args[:entity_id]
    
    if entity_id.nil?
      puts colorize("❌ Please provide an entity_id: rails hass:toggle[light.living_room]", :red)
      next
    end

    begin
      # Call exact same service method as tools
      result = HomeAssistantService.toggle(entity_id)
      puts colorize("🔄 Toggled #{entity_id}", :green)
      puts JSON.pretty_generate(result)
    rescue HomeAssistantService::Error => e
      puts colorize("❌ Error: #{e.message}", :red)
    end
  end

  desc "List all available services or for specific domain: rails hass:services[light] OR DOMAIN=light rails hass:services"
  task :services, [:domain] => :environment do |_t, args|
    begin
      domain = parse_domain_arg(args)
      
      if domain
        # Call exact same service method as tools
        result = HomeAssistantService.domain_services(domain)
        puts colorize("🔧 Services for #{domain}:", :cyan)
        puts JSON.pretty_generate(result)
      else
        # Call exact same service method as tools
        result = HomeAssistantService.services
        puts colorize("🔧 All services:", :cyan)
        puts JSON.pretty_generate(result)
      end
    rescue HomeAssistantService::Error => e
      puts colorize("❌ Error: #{e.message}", :red)
    end
  end

  desc "Call a service: rails hass:service[light,turn_on,light.living_room] OR DOMAIN=light SERVICE=turn_on ENTITY=light.living_room rails hass:service"
  task :service, [:domain, :service, :entity_id] => :environment do |_t, args|
    domain = parse_domain_arg(args)
    service = get_arg(args, :service, 'SERVICE')
    entity_id = parse_entity_arg(args)
    
    if domain.nil? || service.nil?
      puts colorize("❌ Please provide domain and service: DOMAIN=light SERVICE=turn_on rails hass:service", :red)
      next
    end

    begin
      service_data = {}
      service_data[:entity_id] = entity_id if entity_id

      # Call exact same service method as tools
      result = HomeAssistantService.call_service(domain, service, service_data)
      puts colorize("✅ Called #{domain}.#{service}", :green)
      puts colorize("Service data: #{service_data}", :blue)
      puts JSON.pretty_generate(result)
    rescue HomeAssistantService::Error => e
      puts colorize("❌ Error: #{e.message}", :red)
    end
  end

  desc "Watch entity state changes: rails hass:watch[sensor.temperature]"
  task :watch, [:entity_id] => :environment do |_t, args|
    entity_id = args[:entity_id]
    
    if entity_id.nil?
      puts colorize("❌ Please provide an entity_id: rails hass:watch[sensor.temperature]", :red)
      next
    end

    puts colorize("👁  Watching #{entity_id} (Press Ctrl+C to stop)", :cyan)
    puts colorize("─" * 50, :blue)

    last_state = nil
    last_attributes = nil

    begin
      loop do
        entity = HomeAssistantService.entity(entity_id)
        
        if entity.nil?
          puts colorize("❌ Entity '#{entity_id}' not found", :red)
          break
        end

        current_state = entity['state']
        current_attributes = entity['attributes']

        if current_state != last_state
          timestamp = Time.current.strftime("%H:%M:%S")
          puts "#{colorize("[#{timestamp}]", :blue)} State: #{colorize(last_state, :red)} → #{colorize(current_state, :green)}"
          last_state = current_state
        end

        if current_attributes != last_attributes
          timestamp = Time.current.strftime("%H:%M:%S")
          puts "#{colorize("[#{timestamp}]", :blue)} Attributes updated"
          last_attributes = current_attributes
        end

        sleep 2
      end
    rescue Interrupt
      puts colorize("\n👋 Stopped watching #{entity_id}", :yellow)
    rescue HomeAssistantService::Error => e
      puts colorize("❌ Error: #{e.message}", :red)
    end
  end

  # Helper methods
  private

  def colorize(text, color)
    case color
    when :red
      "\e[31m#{text}\e[0m"
    when :green
      "\e[32m#{text}\e[0m"
    when :yellow
      "\e[33m#{text}\e[0m"
    when :blue
      "\e[34m#{text}\e[0m"
    when :magenta
      "\e[35m#{text}\e[0m"
    when :cyan
      "\e[36m#{text}\e[0m"
    when :white
      "\e[37m#{text}\e[0m"
    else
      text
    end
  end

  def state_color(state)
    case state.to_s.downcase
    when 'on', 'open', 'home', 'active', 'armed'
      :green
    when 'off', 'closed', 'away', 'inactive', 'disarmed'
      :red
    when 'unavailable', 'unknown', 'error'
      :yellow
    else
      :white
    end
  end
end

# Add description for the namespace
desc "Home Assistant integration tasks"
task :hass do
  puts colorize("🏠 Home Assistant Rake Tasks", :cyan)
  puts colorize("=" * 30, :blue)
  puts
  puts colorize("Connection:", :yellow)
  puts "  rails hass:test                     - Test connection to Home Assistant"
  puts
  puts colorize("Entities:", :yellow)
  puts "  rails hass:entities                 - List all entities"
  puts "  rails hass:entities[domain]         - List entities by domain (light, sensor, etc.)"
  puts "  rails hass:entity[entity_id]        - Get detailed entity information"
  puts
  puts colorize("State Management:", :yellow)
  puts "  rails hass:get[entity_id]           - Get entity state"
  puts "  rails hass:set[entity_id,state]     - Set entity state"
  puts "  rails hass:turn_on[entity_id]       - Turn on entity"
  puts "  rails hass:turn_off[entity_id]      - Turn off entity"
  puts "  rails hass:toggle[entity_id]        - Toggle entity"
  puts
  puts colorize("Services:", :yellow)
  puts "  rails hass:services                 - List all service domains"
  puts "  rails hass:services[domain]         - List services for domain"
  puts "  rails hass:service[domain,service,entity_id] - Call a service"
  puts
  puts colorize("Development:", :yellow)
  puts "  rails hass:watch[entity_id]         - Watch entity for changes"
  puts
  puts colorize("Examples:", :green)
  puts "  rails hass:entities[light]"
  puts "  rails hass:turn_on[light.living_room]"
  puts "  rails hass:get[sensor.temperature]"
  puts "  rails hass:service[light,turn_on,light.kitchen]"
end