# app/services/persona_switch_service.rb

class PersonaSwitchService
  class << self
    # Handle persona switching with full theatrical experience
    def handle_persona_switch(new_persona_id, previous_persona_id = nil)
      Rails.logger.info "🎭 EPIC PERSONA SWITCH: #{previous_persona_id || 'unknown'} → #{new_persona_id}"

      # Load persona theme configuration
      theme_config = load_persona_themes
      persona_config = theme_config.dig("personas", new_persona_id.to_s) || {}

      # Execute the full persona switch experience
      execute_persona_switch_sequence(new_persona_id, previous_persona_id, persona_config, theme_config)

      # Handle goal awareness after the theatrics
      handle_goal_awareness(new_persona_id, previous_persona_id)
    end

    private

    # Load persona themes configuration
    def load_persona_themes
      config_path = Rails.root.join("config", "persona_themes.yml")
      YAML.load_file(config_path)
    rescue StandardError => e
      Rails.logger.error "❌ Failed to load persona themes: #{e.message}"
      { "defaults" => {}, "personas" => {} }
    end

    # Execute the full persona switch sequence with theatrics
    def execute_persona_switch_sequence(new_persona_id, previous_persona_id, persona_config, theme_config)
      defaults = theme_config["defaults"] || {}

      Rails.logger.info "🎬 Starting persona switch sequence for #{new_persona_id}"

      # Phase 1: Entrance chime and initial light effect
      play_entrance_chime(persona_config)
      trigger_entrance_lights(new_persona_id, persona_config)

      # Phase 2: Start theme music
      theme_duration = persona_config["theme_duration"] || defaults["theme_duration"] || 30
      play_theme_music(new_persona_id, persona_config, theme_duration)

      # Phase 3: Light show during theme music
      trigger_theme_light_show(new_persona_id, persona_config)

      # Phase 4: Async LLM-powered announcement after delay
      announcement_delay = persona_config["announcement_delay"] || defaults["announcement_delay"] || 5
      schedule_llm_announcement(new_persona_id, previous_persona_id, announcement_delay)

      # Phase 5: Post-announcement random effects
      post_effects_duration = persona_config["post_announcement_effects"] || defaults["post_announcement_effects"] || 10
      schedule_post_announcement_effects(new_persona_id, persona_config, post_effects_duration, theme_duration)

      Rails.logger.info "🎭✨ Persona switch sequence initiated for #{new_persona_id}"
    end

    # Play entrance chime sound
    def play_entrance_chime(persona_config)
      return unless persona_config.dig("sound_effects", "entrance_chime")

      begin
        HomeAssistantService.call_service(
          "media_player",
          "play_media",
          {
            entity_id: "media_player.square_voice",
            media_content_id: persona_config.dig("sound_effects", "entrance_chime"),
            media_content_type: "audio/wav"
          }
        )
        Rails.logger.info "🔔 Played entrance chime"
      rescue StandardError => e
        Rails.logger.warn "⚠️ Failed to play entrance chime: #{e.message}"
      end
    end

    # Trigger entrance light effects
    def trigger_entrance_lights(persona_id, persona_config)
      return unless persona_config.dig("light_effects", "entrance")

      begin
        effect_name = persona_config.dig("light_effects", "entrance")
        color = persona_config.dig("color_palette")&.first || "#FFFFFF"

        # Apply to both cube lights
        [ "light.cube_light_top", "light.cube_inner" ].each do |entity_id|
          HomeAssistantService.call_service(
            "light",
            "turn_on",
            {
              entity_id: entity_id,
              effect: effect_name,
              rgb_color: hex_to_rgb(color),
              brightness: 255
            }
          )
        end
        Rails.logger.info "💡 Triggered entrance lights: #{effect_name} in #{color}"
      rescue StandardError => e
        Rails.logger.warn "⚠️ Failed to trigger entrance lights: #{e.message}"
      end
    end

    # Play theme music for the persona
    def play_theme_music(persona_id, persona_config, duration)
      return unless persona_config["theme_song"]

      begin
        HomeAssistantService.call_service(
          "media_player",
          "play_media",
          {
            entity_id: "media_player.square_voice",
            media_content_id: persona_config["theme_song"],
            media_content_type: "music"
          }
        )
        Rails.logger.info "🎵 Playing theme music: #{persona_config['theme_song']} for #{duration}s"
      rescue StandardError => e
        Rails.logger.warn "⚠️ Failed to play theme music: #{e.message}"
      end
    end

    # Trigger light show during theme music
    def trigger_theme_light_show(persona_id, persona_config)
      return unless persona_config.dig("light_effects", "during_theme")

      begin
        effect_name = persona_config.dig("light_effects", "during_theme")
        colors = persona_config["color_palette"] || [ "#FFFFFF" ]

        # Apply theme effects to cube lights
        [ "light.cube_light_top", "light.cube_inner" ].each_with_index do |entity_id, index|
          color = colors[index % colors.length]
          HomeAssistantService.call_service(
            "light",
            "turn_on",
            {
              entity_id: entity_id,
              effect: effect_name,
              rgb_color: hex_to_rgb(color),
              brightness: 200
            }
          )
        end
        Rails.logger.info "🌈 Theme light show activated: #{effect_name}"
      rescue StandardError => e
        Rails.logger.warn "⚠️ Failed to trigger theme light show: #{e.message}"
      end
    end

    # Schedule LLM-powered announcement
    def schedule_llm_announcement(new_persona_id, previous_persona_id, delay)
      Thread.new do
        sleep delay
        make_llm_powered_announcement(new_persona_id, previous_persona_id)
      end
    end

    # Schedule post-announcement random effects
    def schedule_post_announcement_effects(persona_id, persona_config, effects_duration, total_theme_duration)
      announcement_delay = persona_config["announcement_delay"] || 5
      effects_start_time = announcement_delay + 8  # 8 seconds for announcement

      Thread.new do
        sleep effects_start_time
        trigger_random_post_effects(persona_id, persona_config, effects_duration)
      end
    end

    # Make LLM-powered context-aware announcement
    def make_llm_powered_announcement(new_persona_id, previous_persona_id)
      begin
        persona_instance = get_persona_instance(new_persona_id)
        return unless persona_instance

        # Build context for the announcement
        context = build_arrival_context(new_persona_id, previous_persona_id)

        # Get persona's system prompt
        system_prompt = get_persona_system_prompt(persona_instance)

        # Create announcement message
        user_message = build_arrival_announcement_prompt(context)

        messages = [
          { role: "system", content: system_prompt },
          { role: "user", content: user_message }
        ]

        Rails.logger.info "🎤 Generating LLM announcement for #{new_persona_id}"

        response = LlmService.call_with_tools(
          messages: messages,
          model: Rails.configuration.default_ai_model,
          temperature: 0.9  # High creativity for personality
        )

        announcement = response.dig("choices", 0, "message", "content")&.strip
        if announcement
          # Play the announcement
          persona_voice = get_persona_voice(new_persona_id)
          HomeAssistantService.call_service(
            "music_assistant",
            "announce",
            {
              message: announcement,
              voice: persona_voice,
              entity_id: "media_player.square_voice"
            }
          )
          Rails.logger.info "🎭 LLM Announcement: #{announcement[0..100]}..."
        end

      rescue StandardError => e
        Rails.logger.error "❌ Failed to make LLM announcement: #{e.message}"
        # Fallback to simple announcement
        fallback_announcement = build_simple_announcement(new_persona_id)
        HomeAssistantService.call_service(
          "tts",
          "cloud_say",
          {
            entity_id: "media_player.square_voice",
            message: fallback_announcement
          }
        )
      end
    end

    # Build context for persona arrival
    def build_arrival_context(new_persona_id, previous_persona_id)
      current_time = Time.current
      room_info = get_current_room_info
      current_goal = GoalService.current_goal_status

      {
        previous_persona: previous_persona_id ? previous_persona_id.to_s.capitalize : "another persona",
        time_of_day: current_time.strftime("%l:%M %p").strip,
        day_period: get_day_period(current_time),
        location: room_info[:room] || "the space",
        occupancy: room_info[:occupied] ? "occupied" : "quiet",
        current_goal: current_goal ? current_goal[:goal_description] : nil,
        weather: get_weather_info
      }
    end

    # Build prompt for LLM-powered arrival announcement
    def build_arrival_announcement_prompt(context)
      "🎭 You've just become the active persona on the GlitchCube! Here's your situation:\n\n" +
      "• Previous persona: #{context[:previous_persona]} was just here\n" +
      "• Time: #{context[:time_of_day]} on #{context[:day_period]}\n" +
      "• Location: Currently in #{context[:location]} (#{context[:occupancy]})\n" +
      "• Current goal: #{context[:current_goal] || 'No active goal'}\n" +
      "• Weather: #{context[:weather]}\n\n" +
      "Make your arrival announcement! In 2-3 sentences:\n" +
      "1. Introduce yourself with your personality\n" +
      "2. Orient yourself to the situation\n" +
      "3. Show awareness of what's happening or express curiosity\n\n" +
      "Be authentic to your persona and make people aware that something exciting just happened!"
    end

    # Trigger random post-announcement effects
    def trigger_random_post_effects(persona_id, persona_config, duration)
      return unless persona_config.dig("light_effects", "post_announcement")

      begin
        effects = persona_config.dig("light_effects", "post_announcement") || []
        colors = persona_config["color_palette"] || [ "#FFFFFF" ]

        # Change effects every 3 seconds
        changes = (duration / 3).to_i

        changes.times do |i|
          effect = effects.sample
          color = colors.sample

          [ "light.cube_light_top", "light.cube_inner" ].each do |entity_id|
            HomeAssistantService.call_service(
              "light",
              "turn_on",
              {
                entity_id: entity_id,
                effect: effect,
                rgb_color: hex_to_rgb(color),
                brightness: 180
              }
            )
          end

          Rails.logger.info "🎆 Post-announcement effect #{i+1}: #{effect} in #{color}"
          sleep 3 unless i == changes - 1
        end
      rescue StandardError => e
        Rails.logger.warn "⚠️ Failed to trigger post-announcement effects: #{e.message}"
      end
    end

    # Convert hex color to RGB array
    def hex_to_rgb(hex)
      hex = hex.gsub("#", "")
      [ hex[0..1].to_i(16), hex[2..3].to_i(16), hex[4..5].to_i(16) ]
    end

    # Get persona voice ID from config
    def get_persona_voice(persona_id)
      begin
        config_path = Rails.root.join("lib", "prompts", "personas", "#{persona_id}.yml")
        if File.exist?(config_path)
          config = YAML.load_file(config_path)
          config["voice_id"]
        end
      rescue StandardError => e
        Rails.logger.warn "Failed to load voice for #{persona_id}: #{e.message}"
        nil
      end
    end

    # Simple fallback announcement
    def build_simple_announcement(persona_id)
      case persona_id.to_sym
      when :buddy then "Hello there! Buddy here, ready to help!"
      when :jax then "Jax is in the house! Let's turn this place up!"
      when :neon then "S-s-serving you realness! Neon's here, hunty!"
      when :sparkle then "Ooh, sparkles! I'm here and ready to dazzle!"
      when :zorp then "Greetings, humans. This is Zorp."
      when :crash then "Systems rebooted! Crash online and operational."
      when :mobius then "The infinite loop begins again. Mobius speaking."
      when :thecube then "I am The Cube. The eternal observer returns."
      else "A new voice emerges from the cube."
      end
    end

    # Get current room information
    def get_current_room_info
      begin
        motion_sensor = HomeAssistantService.entity("binary_sensor.living_room_motion")
        occupied = motion_sensor&.dig("state") == "on"
        { room: "living room", occupied: occupied }
      rescue
        { room: "the space", occupied: false }
      end
    end

    # Get day period
    def get_day_period(time)
      hour = time.hour
      case hour
      when 5..11 then "a #{%w[beautiful sunny bright].sample} morning"
      when 12..16 then "a #{%w[lovely warm bright].sample} afternoon"
      when 17..20 then "a #{%w[cozy pleasant nice].sample} evening"
      when 21..23 then "a #{%w[quiet peaceful relaxing].sample} night"
      else "the #{%w[late deep quiet].sample} hours"
      end
    end

    # Get weather info
    def get_weather_info
      begin
        weather = HomeAssistantService.entity("weather.home")
        condition = weather&.dig("state") || "unknown"
        temp = weather&.dig("attributes", "temperature")
        temp_str = temp ? "#{temp}°" : ""
        "#{condition} #{temp_str}".strip
      rescue
        "pleasant"
      end
    end

    # Handle goal awareness after theatrics
    def handle_goal_awareness(new_persona_id, previous_persona_id)
      # Get current goal status
      current_goal = GoalService.current_goal_status

      if current_goal
        # Existing goal - ask new persona if they want to keep it
        notify_persona_with_goal(new_persona_id, current_goal, previous_persona_id)
      else
        # No current goal - just select a new one
        Rails.logger.info "🎯 No current goal found, selecting new goal for #{new_persona_id}"
        GoalService.select_goal
        notify_persona_new_goal(new_persona_id)
      end
    end

    # Notify persona about existing goal and let them decide
    def notify_persona_with_goal(persona_id, current_goal, previous_persona_id)
      persona_instance = get_persona_instance(persona_id)
      return unless persona_instance

      # Calculate progress percentage
      progress_percentage = calculate_goal_progress(current_goal)

      # Get persona's system prompt
      system_prompt = get_persona_system_prompt(persona_instance)

      # Create conversational message
      user_message = build_goal_continuation_message(
        current_goal,
        progress_percentage,
        previous_persona_id
      )

      # Send LLM message
      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: user_message }
      ]

      Rails.logger.info "💬 Sending goal continuation message to #{persona_id}"
      Rails.logger.debug "📝 Message: #{user_message}"

      begin
        response = LlmService.call_with_tools(
          messages: messages,
          model: Rails.configuration.default_ai_model,
          temperature: 0.8 # Slightly more creative for persona personality
        )

        response_content = response.dig("choices", 0, "message", "content")
        Rails.logger.info "🎭 #{persona_id} response: #{response_content&.first(200)}..."

        # Check if persona wants to change goal
        if wants_new_goal?(response_content)
          Rails.logger.info "🔄 #{persona_id} requested a new goal"
          GoalService.request_new_goal(reason: "persona_#{persona_id}_request")
        else
          Rails.logger.info "✅ #{persona_id} decided to continue current goal"
        end

      rescue StandardError => e
        Rails.logger.error "❌ Failed to notify persona about goal: #{e.message}"
        # Fallback: continue with current goal
      end
    end

    # Notify persona about newly selected goal
    def notify_persona_new_goal(persona_id)
      persona_instance = get_persona_instance(persona_id)
      return unless persona_instance

      new_goal = GoalService.current_goal_status
      return unless new_goal

      # Get persona's system prompt
      system_prompt = get_persona_system_prompt(persona_instance)

      # Create message about new goal
      user_message = build_new_goal_message(new_goal)

      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: user_message }
      ]

      Rails.logger.info "🎯 Notifying #{persona_id} about new goal"

      begin
        response = LlmService.call_with_tools(
          messages: messages,
          model: Rails.configuration.default_ai_model,
          temperature: 0.8
        )

        response_content = response.dig("choices", 0, "message", "content")
        Rails.logger.info "🎭 #{persona_id} new goal response: #{response_content&.first(200)}..."

      rescue StandardError => e
        Rails.logger.error "❌ Failed to notify persona about new goal: #{e.message}"
      end
    end

    # Get persona instance from ID
    def get_persona_instance(persona_id)
      case persona_id.to_sym
      when :buddy then Personas::BuddyPersona.new
      when :jax then Personas::JaxPersona.new
      when :sparkle then Personas::SparklePersona.new
      when :zorp then Personas::ZorpPersona.new
      when :lomi then Personas::LomiPersona.new
      when :crash then Personas::CrashPersona.new
      when :neon then Personas::NeonPersona.new
      when :mobius then Personas::MobiusPersona.new
      when :thecube then Personas::ThecubePersona.new
      else
        Rails.logger.warn "⚠️ Unknown persona: #{persona_id}"
        nil
      end
    end

    # Get system prompt from persona
    def get_persona_system_prompt(persona_instance)
      result = persona_instance.process_message("", {})
      result[:system_prompt] || "You are #{persona_instance.name}, a unique AI persona in the GlitchCube."
    rescue StandardError => e
      Rails.logger.error "Failed to get system prompt: #{e.message}"
      "You are #{persona_instance.name}, a unique AI persona in the GlitchCube."
    end

    # Calculate goal progress as percentage
    def calculate_goal_progress(goal_status)
      return 0 unless goal_status[:started_at] && goal_status[:time_limit]

      elapsed = Time.current - goal_status[:started_at]
      total_time = goal_status[:time_limit]

      progress = (elapsed.to_f / total_time.to_f * 100).round
      [ progress, 100 ].min # Cap at 100%
    end

    # Build message for goal continuation decision
    def build_goal_continuation_message(goal_status, progress_percentage, previous_persona_id)
      previous_name = previous_persona_id ? previous_persona_id.to_s.capitalize : "the previous persona"

      "🎭 Hello! You just became the active persona on the GlitchCube! #{previous_name} was working on this goal: \"#{goal_status[:goal_description]}\" and was #{progress_percentage}% of the way through the time allocated for it.\n\nDo you want to keep working on this goal, or would you prefer to throw it back and let the cube choose a mysterious new direction? You can't pick your specific goal, but you have the agency to decide whether this current path resonates with you or if you'd rather see what fate has in store!\n\nWhat do you think? Keep going or roll the dice for something new?"
    end

    # Build message for new goal notification
    def build_new_goal_message(goal_status)
      "🎯 Welcome! You're now the active persona on the GlitchCube. Since there was no goal in progress, I've selected a new one for you: \"#{goal_status[:goal_description]}\"\n\nThis is a #{goal_status[:category].humanize} goal, and you have #{(goal_status[:time_limit] / 1.hour).round(1)} hours to work on it. Ready to dive in?"
    end

    # Check if response indicates wanting a new goal
    def wants_new_goal?(response_content)
      return false unless response_content

      # Look for keywords that indicate wanting change
      change_indicators = [
        "new", "different", "change", "roll", "dice", "throw", "back",
        "mysterious", "fate", "something else", "don't want", "not interested"
      ]

      keep_indicators = [
        "keep", "continue", "stay", "maintain", "stick", "carry on", "keep going"
      ]

      response_lower = response_content.downcase

      # Count indicators
      change_count = change_indicators.count { |word| response_lower.include?(word) }
      keep_count = keep_indicators.count { |word| response_lower.include?(word) }

      # If more change indicators than keep indicators, assume they want change
      change_count > keep_count
    end
  end
end
