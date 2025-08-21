# app/services/persona_switch_service.rb

class PersonaSwitchService
  class << self
    # Handle persona switching with goal awareness
    def handle_persona_switch(new_persona_id, previous_persona_id = nil)
      Rails.logger.info "🎭 Persona switching from #{previous_persona_id || 'unknown'} to #{new_persona_id}"

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

    private

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
