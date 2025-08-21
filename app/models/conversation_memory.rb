# frozen_string_literal: true

class ConversationMemory < ApplicationRecord
  vectorsearch

  after_save :upsert_to_vectorsearch

  belongs_to :conversation, foreign_key: :session_id, primary_key: :session_id

  MEMORY_TYPES = %w[preference fact instruction context event].freeze
  IMPORTANCE_RANGE = (1..10).freeze

  validates :session_id, presence: true
  validates :summary, presence: true
  validates :memory_type, presence: true, inclusion: { in: MEMORY_TYPES }
  validates :importance, presence: true, inclusion: { in: IMPORTANCE_RANGE }

  scope :by_session, ->(session_id) { where(session_id: session_id) }
  scope :by_type, ->(type) { where(memory_type: type) }
  scope :by_importance, ->(importance) { where(importance: importance) }
  scope :high_importance, -> { where(importance: 7..10) }
  scope :medium_importance, -> { where(importance: 4..6) }
  scope :low_importance, -> { where(importance: 1..3) }
  scope :recent, -> { order(created_at: :desc) }

  # Dynamic scopes for all memory types
  MEMORY_TYPES.each do |type|
    scope type.to_sym, -> { where(memory_type: type) }
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

  def high_importance?
    importance >= 7
  end

  def medium_importance?
    importance.between?(4, 6)
  end

  def low_importance?
    importance <= 3
  end
end
