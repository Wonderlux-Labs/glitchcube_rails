# app/jobs/world_state_updaters/narrative_conversation_sync_job.rb

class WorldStateUpdaters::NarrativeConversationSyncJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(conversation_log_id)
    conversation_log = ConversationLog.find(conversation_log_id)
    WorldStateUpdaters::NarrativeConversationSyncService.sync_conversation(conversation_log)
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "ConversationLog #{conversation_log_id} not found for HA sync: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "Failed to sync conversation #{conversation_log_id} to HA: #{e.message}"
    raise e # Re-raise to trigger retry
  end
end
