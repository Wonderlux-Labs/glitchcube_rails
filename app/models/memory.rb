# frozen_string_literal: true

# A discrete thing the cube remembers about people, events, or the world.
# Searched on demand by MemorySearchService via plain Rails queries — no
# embeddings. The `embedding` column is retained but unused. Writing is not wired
# into the persona turn; a future background consolidator job owns population.
class Memory < ApplicationRecord
  CATEGORIES = %w[fact event person preference vibe].freeze
  IMPORTANCE_RANGE = (1..10).freeze

  validates :content, presence: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :importance, presence: true, inclusion: { in: IMPORTANCE_RANGE }

  scope :recent, -> { order(created_at: :desc) }
  scope :by_category, ->(category) { where(category: category) }
  scope :high_importance, -> { where(importance: 7..10) }
  scope :upcoming, -> { where.not(occurs_at: nil).where(occurs_at: Time.current..).order(occurs_at: :asc) }

  CATEGORIES.each do |category|
    scope category.to_sym, -> { where(category: category) }
  end

  # Plain keyword/category/time search — the deep-recall path. No embedding call.
  def self.search(query: nil, category: nil, on_or_after: nil, on_or_before: nil, limit: 5)
    scope = all
    scope = scope.by_category(category) if category.present? && CATEGORIES.include?(category)
    scope = scope.where("content ILIKE ?", "%#{sanitize_sql_like(query)}%") if query.present?
    scope = scope.where(occurs_at: on_or_after..) if on_or_after
    scope = scope.where(occurs_at: ..on_or_before) if on_or_before

    # Time-relevant memories sort by when they happen; the rest by importance.
    scope = (on_or_after || on_or_before) ? scope.order(occurs_at: :asc) : scope.order(importance: :desc, created_at: :desc)
    scope.limit(limit)
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
end
