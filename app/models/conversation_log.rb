class ConversationLog < ApplicationRecord
  belongs_to :conversation, foreign_key: :session_id, primary_key: :session_id

  validates :session_id, presence: true
  validates :user_message, presence: true
  validates :ai_response, presence: true

  scope :by_session, ->(session_id) { where(session_id: session_id) }
  scope :recent, -> { order(created_at: :desc) }
  scope :chronological, -> { order(created_at: :asc) }


  def tool_results_json
    return {} if tool_results.blank?
    JSON.parse(tool_results)
  rescue JSON::ParserError
    {}
  end

  def metadata_json
    return {} if metadata.blank?
    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end

  def tool_results_json=(hash)
    self.tool_results = hash.to_json
  end

  def metadata_json=(hash)
    self.metadata = hash.to_json
  end

  # Token/cost usage for this turn's brain call (see LlmIntention#usage_for),
  # or {} on turns before this was tracked / where the LLM call failed.
  def usage
    metadata_json["usage"] || {}
  end

  # Full-fidelity rendering for the summarizers: the visitor line, what the persona
  # said, its private thought, and the device actions it ATTEMPTED that turn. Lets a
  # summary observe what actually happened (including whether actions had any effect),
  # not just the spoken words.
  def transcript_line
    narrative = metadata_json["narrative"] || {}
    lines = [ "Visitor: #{user_message}" ]
    thought = narrative["inner_monologue"].presence
    lines << (thought ? "Cube (privately: #{thought}): #{ai_response}" : "Cube: #{ai_response}")

    # The brain returns plain-English action channels as top-level keys
    # (lights/sound/marquee/other_actions, plus any other non-narrative key). Anything
    # that isn't a narrative key is an attempted device action.
    actions = narrative
              .except(*Schemas::NarrativeResponseSchema::NARRATIVE_KEYS)
              .filter_map { |channel, desc| "#{channel}: #{desc}".presence if desc.present? }
    lines << "  → attempted device actions: #{actions.join('; ')}" if actions.any?
    lines.join("\n")
  end
end
