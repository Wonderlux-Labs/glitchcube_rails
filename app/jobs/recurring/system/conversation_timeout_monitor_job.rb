# app/jobs/conversation_timeout_monitor_job.rb

module Recurring
  module System
    class ConversationTimeoutMonitorJob < ApplicationJob
  queue_as :default

  def perform
    return unless Rails.env.production? || Rails.env.development?

    Rails.logger.info "🕐 ConversationTimeoutMonitorJob starting"

    timeout_threshold = 5.minutes.ago

    conversations_to_end = Conversation.active
      .joins(:conversation_logs)
      .where(conversation_logs: { created_at: ..timeout_threshold })
      .group("conversations.id")
      .having("MAX(conversation_logs.created_at) < ?", timeout_threshold)

    conversations_to_end.find_each do |conversation|
      Rails.logger.info "⏰ Ending conversation #{conversation.session_id} (last activity: #{conversation.conversation_logs.recent.first&.created_at})"

      conversation.end!
    end

    Rails.logger.info "✅ ConversationTimeoutMonitorJob completed (ended #{conversations_to_end.count} conversations)"
  rescue StandardError => e
    Rails.logger.error "❌ ConversationTimeoutMonitorJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
    end
  end
end
