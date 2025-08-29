# app/services/prompts/system_context_enhancer.rb
module Prompts
  class SystemContextEnhancer
    def self.enhance(base_context, user_message: nil)
      new(base_context, user_message: user_message).enhance
    end

    def initialize(base_context, user_message: nil)
      @base_context = base_context
      @user_message = user_message
    end

    def enhance
      context_parts = [ @base_context ]

      # Add contextual information only for system prompts
      context_parts << build_goal_context if build_goal_context.present?
      context_parts << build_upcoming_events_context if build_upcoming_events_context.present?
      context_parts << build_relevant_knowledge_context if @user_message.present?

      context_parts.compact.join("\n\n")
    end

    private

    def build_goal_context
      @goal_context ||= begin
        parts = []
        if HaDataSync.low_power_mode?
          parts << "⚠️ SAFETY MODE: Low battery - find power! URGENT! GET POWER! URGENT!"
        else
          goal = GoalService.current_goal_status
          return nil unless goal

          parts << "Goal: #{goal[:goal_description]}"
          parts << "Time left: #{format_time_duration(goal[:time_remaining])}" if goal[:time_remaining].to_i > 0

          parts.join(" | ")
        end
      rescue StandardError => e
        Rails.logger.error "Failed to build goal context: #{e.message}"
        nil
      end
    end

    def build_upcoming_events_context
      return nil unless defined?(Event)

      events = Event.high_importance.upcoming.within_hours(24).limit(3)
      return nil if events.empty?

      formatted = events.map { |e| "#{e.title} at #{e.formatted_time}" }.join(", ")
      "Upcoming: #{formatted}"
    end

    def build_relevant_knowledge_context
      return nil unless @user_message.present?

      snippets = []

      # Get relevant summaries only (most useful)
      # TODO: Re-implement similarity search once vectorsearch methods are confirmed
      # if defined?(Summary)
      #   summaries = Summary.similarity_search(@user_message).limit(2)
      #   summaries.each do |summary|
      #     snippets << summary.summary_text.truncate(120)
      #   end
      # end

      snippets.empty? ? nil : "Related: #{snippets.join(' • ')}"
    end

    def format_time_duration(seconds)
      if seconds < 60
        "#{seconds.to_i}s"
      elsif seconds < 3600
        "#{(seconds / 60).to_i}m"
      else
        hours = (seconds / 3600).to_i
        minutes = ((seconds % 3600) / 60).to_i
        "#{hours}h #{minutes}m"
      end
    end

    def safety_mode_message
      "⚡ LOW BATTERY - NEED POWER! Battery at 21% and dropping"
    end
  end
end
