# frozen_string_literal: true

class Summary < ApplicationRecord
  SUMMARY_TYPES = %w[hourly daily session topic].freeze

  validates :summary_text, presence: true
  validates :summary_type, presence: true, inclusion: { in: SUMMARY_TYPES }
  validates :message_count, presence: true, numericality: { greater_than: 0 }

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
end