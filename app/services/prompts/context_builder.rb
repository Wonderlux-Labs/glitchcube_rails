# app/services/prompts/context_builder.rb
module Prompts
  class ContextBuilder
    def self.build(conversation:, extra_context: {}, user_message: nil)
      new(conversation: conversation, extra_context: extra_context, user_message: user_message).build
    end

    def initialize(conversation:, extra_context:, user_message: nil)
      @conversation = conversation
      @extra_context = extra_context
      @user_message = user_message
    end

    def build
      context_parts = []

      # Basic context
      context_parts << "Time: #{Time.current.strftime('%l:%M %p on %A')}"

      # Additional context
      context_parts << build_cube_mode_context if build_cube_mode_context.present?
      context_parts << build_session_context if build_session_context.present?
      context_parts << build_source_context if build_source_context.present?
      context_parts << build_tool_results_context if build_tool_results_context.present?
      context_parts << build_time_context_from_ha if build_time_context_from_ha.present?

      context_parts.compact.join("\n")
    end

    private

    def build_cube_mode_context
      @cube_mode_context ||= begin
        cube_mode = HaDataSync.entity_state("sensor.cube_mode")
        return nil if cube_mode.blank? || cube_mode == "unavailable"

        "Cube mode: #{cube_mode}"
      rescue => e
        Rails.logger.warn "⚠️ Could not fetch sensor.cube_mode state for context: #{e.message}"
        nil
      end
    end

    def build_session_context
      return nil unless @conversation

      [
        "Session: #{@conversation.session_id}",
        "Message count: #{@conversation.messages.count}",
        "Should end?: Think about wrapping up if we are over 10 messages or so!"
      ].join("\n")
    end

    def build_source_context
      return nil unless @extra_context[:source]

      "Source: #{@extra_context[:source]}"
    end

    def build_tool_results_context
      return nil unless @extra_context[:tool_results]&.any?

      results = @extra_context[:tool_results].map do |tool_name, result|
        status = result[:success] ? "✅ SUCCESS" : "❌ FAILED"
        "  #{tool_name}: #{status} - #{result[:message] || result[:error]}"
      end

      "Recent tool results:\n#{results.join("\n")}"
    end

    def build_time_context_from_ha
      begin
        time_of_day = HaDataSync.get_context_attribute("time_of_day")
        day_of_week = HaDataSync.get_context_attribute("day_of_week")
        location = HaDataSync.get_context_attribute("current_location")

        return nil unless time_of_day

        time_context = "Current time context: It is #{time_of_day}"
        time_context += " on #{day_of_week}" if day_of_week
        time_context += " at #{location}" if location
        time_context
      rescue => e
        Rails.logger.warn "Failed to inject time context: #{e.message}"
        nil
      end
    end
  end
end
