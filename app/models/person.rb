# frozen_string_literal: true

class Person < ApplicationRecord
  vectorsearch

  after_save :upsert_to_vectorsearch

  validates :name, presence: true
  validates :description, presence: true
  validates :extracted_from_session, presence: true

  scope :recent, -> { order(last_seen_at: :desc) }
  scope :by_relationship, ->(relationship) { where(relationship: relationship) }
  scope :seen_recently, -> { where("last_seen_at > ?", 1.week.ago) }

  # Associations with summaries and events via extracted_from_session
  def related_summaries
    Summary.where("metadata @> ?", { conversation_ids: [ extracted_from_session ] }.to_json)
  end

  def related_events
    Event.where(extracted_from_session: extracted_from_session)
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

  # Update last seen time when person is mentioned again
  def update_last_seen!(session_id = nil)
    update!(
      last_seen_at: Time.current,
      extracted_from_session: session_id || extracted_from_session
    )
  end

  # Find or create person by name and update their information
  def self.find_or_update_person(name:, description:, session_id:, relationship: nil, additional_metadata: {})
    # First try exact name match
    person = find_by(name: name)

    if person
      # Update existing person with new information
      person.description = [ person.description, description ].compact.join(" | ").truncate(1000)
      person.relationship = relationship if relationship.present?
      person.last_seen_at = Time.current
      person.extracted_from_session = session_id

      # Merge metadata
      current_metadata = person.metadata_json
      person.metadata_json = current_metadata.merge(additional_metadata)

      person.save!
    else
      # Create new person
      person = create!(
        name: name,
        description: description,
        relationship: relationship,
        last_seen_at: Time.current,
        extracted_from_session: session_id,
        metadata: additional_metadata.to_json
      )
    end

    person
  end

  # Search content for embedding includes name and description
  def vectorsearch_fields_content
    "#{name}: #{description}"
  end

  private

  def vectorsearch_fields
    {
      content: vectorsearch_fields_content
    }
  end
end
