# frozen_string_literal: true

class Summary < ApplicationRecord
  # persona summaries belong to a persona; recent/overall summaries do not.
  belongs_to :persona, optional: true

  # `interaction` — the rolling every-N-minutes interaction summary (SummarizerService).
  # `overall`     — the evolving long-term summary folding interaction summaries together
  #                 (OverallSummarizerService); versioned, latest is "the" overall.
  # `persona`     — a persona's own evolving memory + self-steering, written when its stint
  #                 ends (PersonaSummarizerService); versioned, belongs_to a persona.
  #   (Note: none named "recent" — that would collide with the `.recent` ordering scope,
  #   since a per-type scope is defined for every SUMMARY_TYPE below.)
  # `reflection`/`session` predate the amnesiacube refactor.
  SUMMARY_TYPES = %w[interaction overall persona reflection session].freeze

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

  # Plain keyword search over summaries — material for a future trend/long-term
  # job. No embeddings.
  def self.text_search_fallback(question, limit: 10)
    keywords = question.downcase.split(/\W+/).reject(&:blank?)
    return none if keywords.empty?

    search_conditions = keywords.map { "summary_text ILIKE ? OR metadata ILIKE ?" }.join(" OR ")
    search_values = keywords.flat_map { |keyword| [ "%#{keyword}%", "%#{keyword}%" ] }

    where(search_conditions, *search_values)
      .order(created_at: :desc)
      .limit(limit)
  end
end
