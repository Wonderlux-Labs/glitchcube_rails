class Conversation < ApplicationRecord
  has_many :messages, dependent: :destroy
  has_many :conversation_logs, foreign_key: :session_id, primary_key: :session_id, dependent: :destroy
  has_many :conversation_memories, foreign_key: :session_id, primary_key: :session_id, dependent: :destroy

  validates :session_id, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(ended_at: nil) }
  scope :by_persona, ->(persona) { where(persona: persona) }
  scope :finished, -> { where.not(ended_at: nil) }

  def flow_data_json
    return {} if flow_data.blank?
    JSON.parse(flow_data)
  rescue JSON::ParserError
    {}
  end

  def flow_data_json=(hash)
    self.flow_data = hash.to_json
  end

  def metadata_json
    return {} if metadata.blank?
    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end

  def metadata_json=(hash)
    self.metadata = hash.to_json
  end

  def end!
    update!(ended_at: Time.current, continue_conversation: false) unless ended_at
  end

  def finished?
    ended_at.present?
  end

  def finished_ago
    return nil unless ended_at
    Time.current - ended_at
  end

  def active?
    ended_at.nil?
  end

  def duration
    return nil unless started_at
    (ended_at || Time.current) - started_at
  end

  def add_message(role:, content:, **attrs)
    messages.create!(
      role: role,
      content: content,
      **attrs
    )
  end

  def summary
    return @summary if @summary

    @summary = {
      session_id: session_id,
      message_count: message_count,
      persona: persona,
      total_cost: total_cost,
      total_tokens: total_tokens,
      duration: duration,
      started_at: started_at,
      ended_at: ended_at,
      last_message: messages.last&.content
    }
  end

  def update_totals!
    total_tokens = messages.sum("COALESCE(prompt_tokens, 0) + COALESCE(completion_tokens, 0)")
    total_cost = messages.sum("COALESCE(cost, 0)")

    update!(
      total_tokens: total_tokens,
      total_cost: total_cost
    )
  end
end
