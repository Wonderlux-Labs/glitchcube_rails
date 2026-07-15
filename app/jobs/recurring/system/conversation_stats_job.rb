# frozen_string_literal: true

# Pushes conversation-volume metrics to Home Assistant input_number helpers so
# they can be shown on dashboards. Runs every ~5 min (see config/recurring.yml).
#
# A "conversation" is one Conversation session; a "round" is one logged turn
# (a ConversationLog row). The six input_numbers are defined in
# data/homeassistant/packages/glitchcube_core.yaml.
module Recurring
  module System
    class ConversationStatsJob < ApplicationJob
      queue_as :default

      STATS = {
        "input_number.conversations_total" => -> { Conversation.count },
        "input_number.rounds_total" => -> { ConversationLog.count },
        "input_number.conversations_last_6h" => -> { Conversation.where(created_at: 6.hours.ago..).count },
        "input_number.rounds_last_6h" => -> { ConversationLog.where(created_at: 6.hours.ago..).count },
        "input_number.conversations_last_1h" => -> { Conversation.where(created_at: 1.hour.ago..).count },
        "input_number.rounds_last_1h" => -> { ConversationLog.where(created_at: 1.hour.ago..).count }
      }.freeze

      def perform
        hass = HomeAssistantService.new

        STATS.each do |entity_id, count_proc|
          hass.call_service(
            "input_number",
            "set_value",
            entity_id: entity_id,
            value: count_proc.call
          )
        end

        Rails.logger.info "📊 Pushed conversation stats to Home Assistant"
      rescue HomeAssistantService::ConnectionError => e
        Rails.logger.warn "⚠️ Home Assistant unavailable for conversation stats: #{e.message}"
      end
    end
  end
end
