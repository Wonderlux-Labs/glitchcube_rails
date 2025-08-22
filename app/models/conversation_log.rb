class ConversationLog < ApplicationRecord
  belongs_to :conversation, foreign_key: :session_id, primary_key: :session_id

  validates :session_id, presence: true
  validates :user_message, presence: true
  validates :ai_response, presence: true

  scope :by_session, ->(session_id) { where(session_id: session_id) }
  scope :recent, -> { order(created_at: :desc) }
  scope :chronological, -> { order(created_at: :asc) }

  # Automatically sync narrative data to Home Assistant after each conversation
  after_commit :sync_narrative_data_to_ha, on: [ :create, :update ]

  def tool_results_json
    return {} if tool_results.blank?
    JSON.parse(tool_results)
  rescue JSON::ParserError
    {}
  end

  def metadata_json
    return {} if metadata.blank?
    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end

  def tool_results_json=(hash)
    self.tool_results = hash.to_json
  end

  def metadata_json=(hash)
    self.metadata = hash.to_json
  end

  private

  def sync_narrative_data_to_ha
    # Perform HA sync in background to avoid blocking the main thread
    WorldStateUpdaters::NarrativeConversationSyncJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.error "Failed to queue narrative sync job for conversation_log #{id}: #{e&.message}"
  end
end
