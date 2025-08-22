# frozen_string_literal: true

class Event < ApplicationRecord
  vectorsearch

  after_save :upsert_to_vectorsearch

  IMPORTANCE_RANGE = (1..10).freeze

  scope :for_address, -> { where("address ILIKE ?", "%?%") }
  scope :upcoming, -> { where("event_time > ?", Time.current) }
  scope :past, -> { where("event_time <= ?", Time.current) }
  scope :within_hours, ->(hours) { where(event_time: Time.current..(Time.current + hours.hours)) }
  scope :by_location, ->(location) { where(location: location) }
  scope :high_importance, -> { where(importance: 7..10) }
  scope :medium_importance, -> { where(importance: 4..6) }
  scope :low_importance, -> { where(importance: 1..3) }
  scope :recent, -> { order(event_time: :asc) }

  def metadata_json
    return {} if metadata.blank?
    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end

  def metadata_json=(hash)
    self.metadata = hash.to_json
  end

  def upcoming?
    return false unless event_time
    event_time > Time.current
  end

  def high_importance?
    importance >= 7
  end

  def time_until_event
    return nil unless event_time && upcoming?
    event_time - Time.current
  end

  def hours_until_event
    return nil unless upcoming?
    (time_until_event / 1.hour).round(1)
  end

  def formatted_time
    return "No time set" unless event_time
    event_time.strftime("%m/%d at %I:%M %p")
  end

  # Search content includes title, description, and location
  def vectorsearch_fields_content
    content_parts = [ title, description ]
    content_parts << "at #{location}" if location.present?
    content_parts << "on #{formatted_time}" if event_time.present?
    content_parts.join(" ")
  end

  private

  def vectorsearch_fields
    {
      content: vectorsearch_fields_content
    }
  end
end
