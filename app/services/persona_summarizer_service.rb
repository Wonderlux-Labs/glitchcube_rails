# frozen_string_literal: true

# Per-persona fold, run when a persona's stint ends (wired into PersonaSwitchService for the
# OUTGOING persona; also callable manually). In ONE run it:
#   1. FLUSHES any unsummarized tail turns into a final interaction chunk (SummarizerService),
#      so the fold sees the whole stint.
#   2. Reads all of this persona's interaction chunks since its last fold + its prior self-
#      summary, and makes ONE LLM call producing three things: an updated `summary` and
#      `ooc_note` (the persona's private memory + self-steering) and a neutral `handoff_report`.
#   3. Writes TWO rows: a `persona` summary (self memory + steering) and a `handoff` summary
#      (the neutral recap the other personas read and the overall digest folds).
class PersonaSummarizerService
  MODEL = "google/gemini-3.5-flash"
  PERSONA_TYPE = "persona"
  HANDOFF_TYPE = "handoff"
  FIRST_RUN_LOOKBACK = 1.day

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You maintain the memory of ONE persona of the GlitchCube — an interactive art installation
    whose several personas take turns talking to festival-goers. This persona's stint just
    ended. You are given its CHARACTER BRIEF, its current self-summary and self-note (may be
    empty), and the factual chunk summaries of the conversations it just had. Produce THREE
    things, keeping their audiences distinct:

    `summary` — written TO the persona in second person: its own memory of this time on the cube
    — who it talked to, the bits that worked, memorable moments, the feel of its conversations.
    Amend/extend the current self-summary; keep what still matters, add what's new, let trivia
    go. Comfortably under ~180 words.

    `ooc_note` — explicit self-direction this persona will READ before its next conversations.
    FIRST, hold this stint against the CHARACTER BRIEF and flag any drift (meant to be foul-
    mouthed but went polite; warm but turned cold). THEN flag a bit/phrase/move it's overusing,
    something landing badly, or a strength worth keeping. If a prior note flagged something that
    has since improved, AMEND it rather than repeating a stale "never do this." Direct, second
    person, actionable. Empty only if nothing to steer.

    `handoff_report` — a NEUTRAL, journalistic, THIRD-PERSON recap for the OTHER personas and the
    cube's shared memory. This is load-bearing: the next persona sees only the last couple of these,
    and the cube's whole overall memory is built from them, so make it substantive. NOT in this
    persona's voice, NO steering: just what happened this stint — who came by, the arc of it, facts
    and unfinished threads visitors set up, notable moments, what the cube physically attempted (and
    whether it worked). Aim for one to two solid paragraphs (more for a long, eventful stint; less
    for a short quiet one). Another persona should read it and gain real continuity without sounding
    like this one.
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

    SummarizerService.call(@slug) # flush the tail so this fold sees the whole stint

    previous = latest_summary(persona)
    chunks = stint_chunks(persona, previous)
    return ServiceResult.success({ skipped: true, reason: "no new #{@slug} chunks" }) if chunks.empty?

    narrative = generate(persona, previous, chunks)
    text = narrative["summary"].to_s.strip
    return ServiceResult.success({ skipped: true, reason: "empty summary" }) if text.blank?

    summary = persist_persona(persona, previous, text, narrative["ooc_note"], chunks)
    handoff = persist_handoff(persona, narrative["handoff_report"], chunks)
    extras = [ ("+ooc" if summary.metadata_json["ooc_note"].present?),
               ("+handoff ##{handoff.id}" if handoff) ].compact.join(" ")
    Rails.logger.info "🎭 Persona summary ##{summary.id} for #{@slug} from #{chunks.size} chunks #{extras}".strip
    ServiceResult.success({ summary: summary, handoff: handoff })
  rescue => e
    Rails.logger.error "❌ PersonaSummarizerService(#{@slug}) failed: #{e.message}"
    ServiceResult.failure("Persona summarizer failed: #{e.message}")
  end

  private

  def latest_summary(persona)
    persona.summaries.where(summary_type: PERSONA_TYPE).order(:created_at).last
  end

  # This persona's interaction chunks since its last fold (or the first-run lookback).
  def stint_chunks(persona, previous)
    since = previous&.metadata_json&.dig("folded_through_at").then { |t| t ? Time.zone.parse(t) : FIRST_RUN_LOOKBACK.ago }
    Summary.interaction.where(persona_id: persona.id).where("created_at > ?", since).order(:start_time).to_a
  end

  def generate(persona, previous, chunks)
    response = LlmService.call_with_structured_output(
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: build_material(persona, previous, chunks) }
      ],
      response_format: Schemas::PersonaSummarySchema.schema,
      model: MODEL
    )
    response.structured_output || {}
  end

  def build_material(persona, previous, chunks)
    <<~MATERIAL
      PERSONA: #{persona.name || persona.slug}

      CHARACTER BRIEF (who this persona is MEANT to be — judge on-model/off-model against this):
      #{persona.persona_prompt.presence || '(no brief on file)'}

      YOUR CURRENT SELF-SUMMARY (amend/extend — may be empty):
      #{previous&.summary_text.presence || '(none yet — this is your first)'}

      YOUR PRIOR SELF-DIRECTION (amend if things changed — may be empty):
      #{previous&.metadata_json&.dig('ooc_note').presence || '(none)'}

      YOUR STINT, IN FACTUAL CHUNKS (oldest first):
      #{chunks.map { |c| SummaryRenderer.interaction_chunk(c) }.join("\n\n")}
    MATERIAL
  end

  # Versioned — a new persona row each stint, reading the latest as its base.
  # Two different "when" values, deliberately: `end_time` is the end of the conversation data we
  # have (the last chunk's window); `folded_through_at` is the boundary cursor for the NEXT fold —
  # any interaction chunk created after this belongs to a later stint (see #stint_chunks and
  # ContextBuilder#current_stint_chunks, which both key off it).
  def persist_persona(persona, previous, text, ooc_note, chunks)
    Summary.create!(
      persona: persona,
      summary_type: PERSONA_TYPE,
      summary_text: text,
      message_count: (previous&.message_count || 0) + chunks.sum { |c| c.message_count.to_i },
      start_time: previous&.start_time || chunks.first.start_time,
      end_time: chunks.last.end_time,
      metadata: {
        ooc_note: ooc_note.presence,
        folded_through_at: chunks.last.created_at.iso8601(6)
      }.compact.to_json
    )
  end

  # The neutral recap the OTHER personas read and the overall folds. One row per fold,
  # scoped to just this stint's span (not accumulated). Skipped if the model gave nothing.
  def persist_handoff(persona, report, chunks)
    text = report.to_s.strip
    return nil if text.blank?

    Summary.create!(
      persona: persona,
      summary_type: HANDOFF_TYPE,
      summary_text: text,
      message_count: chunks.sum { |c| c.message_count.to_i },
      start_time: chunks.first.start_time,
      end_time: chunks.last.end_time,
      metadata: { folded_through_at: chunks.last.created_at.iso8601(6) }.to_json
    )
  end
end
