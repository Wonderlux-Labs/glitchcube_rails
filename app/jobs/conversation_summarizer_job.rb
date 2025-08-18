# app/jobs/conversation_summarizer_job.rb

class ConversationSummarizerJob < ApplicationJob
  queue_as :default

  def perform
    return unless Rails.env.production? || Rails.env.development?

    Rails.logger.info "🧠 ConversationSummarizerJob starting"

    # Get conversations from the last 30 minutes
    cutoff_time = 30.minutes.ago
    recent_conversation_ids = Conversation.where("updated_at >= ?", cutoff_time).pluck(:id)

    if recent_conversation_ids.any?
      Rails.logger.info "📊 Found #{recent_conversation_ids.count} conversations to summarize"
      WorldStateUpdaters::ConversationSummarizerService.call(recent_conversation_ids)
    else
      Rails.logger.info "😴 No conversations found in the last 30 minutes"
      # Still create an empty summary for record keeping
      WorldStateUpdaters::ConversationSummarizerService.call([])
    end

    Rails.logger.info "✅ ConversationSummarizerJob completed successfully"
  rescue StandardError => e
    Rails.logger.error "❌ ConversationSummarizerJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
end
