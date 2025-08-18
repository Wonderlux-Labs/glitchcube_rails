# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :conversation, counter_cache: :message_count

  validates :role, presence: true, inclusion: { in: %w[user assistant system] }
  validates :content, presence: true

  scope :by_role, ->(role) { where(role: role) }
  scope :recent, -> { order(created_at: :desc) }
  scope :chronological, -> { order(created_at: :asc) }

  def to_api_format
    {
      role: role,
      content: content
    }
  end

  def token_cost
    return nil unless prompt_tokens && completion_tokens && model_used

    {
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: prompt_tokens + completion_tokens,
      model: model_used
    }
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
end