# frozen_string_literal: true

# Per-persona summarizer. Runs when a persona's stint ends (wired into
# PersonaSwitchService for the OUTGOING persona; also callable manually). Reads that
# persona's conversations since its last persona-summary plus its most recent
# persona-summary, and writes a NEW versioned `persona` Summary (belongs_to persona)
# holding that persona's own memory + explicit self-steering. Uses gemini flash.
class PersonaSummarizerService
  MODEL = "google/gemini-3.5-flash"
  PERSONA_TYPE = "persona"
  FIRST_RUN_LOOKBACK = 1.day

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You maintain the private memory and self-direction of ONE persona of the GlitchCube —
    an interactive art installation whose several personas take turns talking to
    festival-goers. This persona's stint just ended; you're updating what it remembers and
    how it should adjust, so the memory persists into its next turn on the cube.

    You are given this persona's CURRENT self-summary (may be empty) and the conversations
    it just had. Produce two things, written TO the persona in second person:

    `summary` — this persona's own memory: who it talked to, the bits that worked, memorable
    moments, the feel of its conversations. More granular than the cube's shared memory, but
    still short — a paragraph, maybe two. Amend/extend the current self-summary; keep what
    still matters, add what's new, let trivia go. Keep it comfortably under ~180 words.

    `ooc_note` — explicit self-direction this persona will READ before its next conversations
    and act on. Flag what to adjust: a bit, phrase, or move it's been overusing ("you keep
    leaning on X — vary it"), something landing badly, or a strength to keep leaning into.
    Crucially, if a prior note flagged something and it's since improved, AMEND it ("you were
    overusing X, but your last stint was well-balanced"). Direct, second person, actionable.
    Empty only if there's genuinely nothing to steer.
  PROMPT

  def self.call(persona_slug)
    new(persona_slug).call
  end

  def initialize(persona_slug)
    @slug = persona_slug.to_s
  end

  def call
    persona = Persona[@slug]
    return ServiceResult.failure("Unknown persona: #{@slug}") unless persona

    previous = latest_summary(persona)
    logs = stint_logs(persona, previous)
    return ServiceResult.success({ skipped: true, reason: "no new #{@slug} conversations" }) if logs.empty?

    narrative = generate(persona, previous, logs)
    text = narrative["summary"].to_s.strip
    return ServiceResult.success({ skipped: true, reason: "empty summary" }) if text.blank?

    summary = persist(persona, previous, text, narrative["ooc_note"], logs)
    Rails.logger.info "🎭 Persona summary ##{summary.id} for #{@slug} from #{logs.size} turns#{' (+ooc)' if summary.metadata_json['ooc_note'].present?}"
    ServiceResult.success({ summary: summary })
  rescue => e
    Rails.logger.error "❌ PersonaSummarizerService(#{@slug}) failed: #{e.message}"
    ServiceResult.failure("Persona summarizer failed: #{e.message}")
  end

  private

  def latest_summary(persona)
    persona.summaries.where(summary_type: PERSONA_TYPE).order(:created_at).last
  end

  # This persona's conversation logs since its last persona-summary was written.
  def stint_logs(persona, previous)
    since = previous&.metadata_json&.dig("folded_through_at").then { |t| t ? Time.zone.parse(t) : FIRST_RUN_LOOKBACK.ago }
    session_ids = Conversation.where(persona: persona.slug).pluck(:session_id)
    return [] if session_ids.empty?

    ConversationLog.where(session_id: session_ids).where("created_at > ?", since).chronological.to_a
  end

  def generate(persona, previous, logs)
    response = LlmService.call_with_structured_output(
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: build_material(persona, previous, logs) }
      ],
      response_format: Schemas::PersonaSummarySchema.schema,
      model: MODEL
    )
    response.structured_output || {}
  end

  def build_material(persona, previous, logs)
    <<~MATERIAL
      PERSONA: #{persona.name || persona.slug}

      YOUR CURRENT SELF-SUMMARY (amend/extend — may be empty):
      #{previous&.summary_text.presence || '(none yet — this is your first)'}

      YOUR PRIOR SELF-DIRECTION (amend if things changed — may be empty):
      #{previous&.metadata_json&.dig('ooc_note').presence || '(none)'}

      YOUR CONVERSATIONS THIS STINT (oldest first):
      #{logs.map { |l| "Visitor: #{l.user_message}\nYou: #{l.ai_response}" }.join("\n\n")}
    MATERIAL
  end

  # Versioned — a new row each stint, reading the latest as its base.
  def persist(persona, previous, text, ooc_note, logs)
    Summary.create!(
      persona: persona,
      summary_type: PERSONA_TYPE,
      summary_text: text,
      message_count: (previous&.message_count || 0) + logs.size,
      start_time: previous&.start_time || logs.first.created_at,
      end_time: logs.last.created_at,
      metadata: {
        ooc_note: ooc_note.presence,
        folded_through_at: logs.last.created_at.iso8601(6)
      }.compact.to_json
    )
  end
end
