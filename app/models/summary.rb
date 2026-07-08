# frozen_string_literal: true

class Summary < ApplicationRecord
  # persona summaries belong to a persona; recent/overall summaries do not.
  belongs_to :persona, optional: true

  # `interaction` — a per-persona, factual chunk summary written every N turns and flushed
  #                 on persona switch (SummarizerService); belongs_to the persona it covers.
  # `overall`     — the evolving long-term digest folding handoff reports together
  #                 (OverallSummarizerService); versioned, latest is "the" overall.
  # `persona`     — a persona's own evolving memory + self-steering, written when its stint
  #                 ends (PersonaSummarizerService); versioned, belongs_to a persona.
  # `handoff`     — a neutral, journalistic recap of a persona's just-ended stint, written
  #                 alongside the `persona` summary for the OTHER personas to read and for the
  #                 overall to fold; belongs_to the persona whose stint it recaps.
  #   (Note: none named "recent" — that would collide with the `.recent` ordering scope,
  #   since a per-type scope is defined for every SUMMARY_TYPE below.)
  # `reflection`/`session` predate the amnesiacube refactor.
  SUMMARY_TYPES = %w[interaction overall persona handoff reflection session].freeze

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

  # Versioned chains: `persona` summaries version per-persona, `overall` versions
  # globally. Same scope also works (harmlessly) for the rolling `interaction`
  # type, which is naturally chronological even though it isn't "versioned".
  def chain
    scope = self.class.where(summary_type: summary_type)
    scope = scope.where(persona_id: persona_id) if persona_id.present?
    scope
  end

  def previous_version
    chain.where("created_at < ?", created_at).order(created_at: :desc).first
  end

  def next_version
    chain.where("created_at > ?", created_at).order(:created_at).first
  end

  def version_number
    chain.where("created_at <= ?", created_at).count
  end

  def version_count
    chain.count
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
