# app/jobs/summaries/conversation_summarizer_job.rb

module Recurring
  module System
    module Summaries
    class ConversationSummarizerJob < ApplicationJob
  queue_as :default

  def perform
    return unless Rails.env.production? || Rails.env.development?

    Rails.logger.info "🧠 ConversationSummarizerJob starting"

    # Get conversations that don't already have an associated conversation summary
    unsummarized_conversation_ids = get_unsummarized_conversations

    if unsummarized_conversation_ids.any?
      Rails.logger.info "📊 Found #{unsummarized_conversation_ids.count} conversations to summarize"
      WorldStateUpdaters::ConversationSummarizerService.call(unsummarized_conversation_ids)
    else
      Rails.logger.info "😴 No unsummarized conversations found - skipping empty summary"
      return
    end

    Rails.logger.info "✅ ConversationSummarizerJob completed successfully"
  rescue StandardError => e
    Rails.logger.error "❌ ConversationSummarizerJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  private

  def get_unsummarized_conversations
    # Get all conversation IDs that are already referenced in Summary metadata
    summarized_ids = []

    Summary.find_each do |summary|
      metadata = summary.metadata_json
      if metadata["conversation_ids"].present?
        summarized_ids.concat(Array(metadata["conversation_ids"]))
      end
    end

    # Get all conversation IDs that aren't in the summarized list
    Conversation.where.not(id: summarized_ids.uniq).pluck(:id)
  end
    end
    end
  end
end
