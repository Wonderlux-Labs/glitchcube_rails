# frozen_string_literal: true

class Summary < ApplicationRecord
  vectorsearch

  after_save :upsert_to_vectorsearch

  SUMMARY_TYPES = %w[hourly daily intermediate session topic goal_completion].freeze

  validates :summary_text, presence: true
  validates :summary_type, presence: true, inclusion: { in: SUMMARY_TYPES }
  validates :message_count, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :by_type, ->(type) { where(summary_type: type) }
  scope :recent, -> { order(created_at: :desc) }
  scope :chronological, -> { order(start_time: :asc) }

  # Dynamic scopes for all summary types
  SUMMARY_TYPES.each do |type|
    scope type.to_sym, -> { where(summary_type: type) }
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

  def duration
    return nil unless start_time && end_time
    end_time - start_time
  end

  def duration_in_minutes
    return nil unless duration
    (duration / 60).round(2)
  end

  # Convenience scope for goal completions
  def self.goal_completions
    where(summary_type: "goal_completion")
  end

  # Get all completed goals with formatted data
  def self.completed_goals
    goal_completions.recent.map do |summary|
      metadata = summary.metadata_json
      {
        goal_id: metadata["goal_id"],
        goal_category: metadata["goal_category"],
        description: summary.summary_text,
        completed_at: summary.created_at,
        duration: metadata["duration_seconds"],
        completion_notes: metadata["completion_notes"],
        expired: metadata["expired"]
      }
    end
  end
end
