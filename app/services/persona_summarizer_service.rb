# frozen_string_literal: true

# Per-persona fold, run when a persona's stint ends (wired into PersonaSwitchService for the
# OUTGOING persona; also callable manually). This is now the KEY summarizer in the pipeline:
# it reads the WHOLE stint's RAW conversation logs (not the rolling interaction chunks), so it
# sees the actual dialogue. In ONE LLM call it produces three things and writes TWO rows:
#   1. a `persona` summary — the persona's own evolving memory + `ooc_note` self-steering
#      (the deepest character steering happens here, grounded in the real transcript), and
#   2. a `handoff` summary — the neutral recap the OTHER personas read AND the source the overall
#      digest folds; it's also where this fold decides which real-world facts get promoted up.
# The rolling interaction chunks are now only for the ACTIVE persona's current-session context —
# the fold no longer reads them, so there's no tail-flush step anymore.
# Runs ~once or twice an hour (on persona switch), so a whole stint of raw turns is fine to pass in.
class PersonaSummarizerService
  PERSONA_TYPE = "persona"
  HANDOFF_TYPE = "handoff"
  FIRST_RUN_LOOKBACK = 1.day

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You maintain the memory of ONE persona of the GlitchCube — an interactive art installation
    whose several personas take turns talking to festival-goers. This persona's stint just ended.
    You are given its CHARACTER BRIEF, its current self-summary and self-note (may be empty), and
    the FULL RAW TRANSCRIPT of every conversation it just had this stint. This is the cube's most
    important summary and you can see the actual dialogue, so be specific. Produce THREE things,
    keeping their audiences distinct:

    `summary` — written TO the persona in second person: its own memory of this time on the cube —
    who it talked to, the bits that worked, memorable moments, the feel of its conversations.
    Amend/extend the current self-summary; keep what still matters, add what's new, let trivia go.
    Comfortably under ~180 words.

    `ooc_note` — explicit self-direction this persona will READ before its next conversations. You
    have the real transcript now, so point at specific moments. FIRST, hold this stint against the
    CHARACTER BRIEF and flag any drift (meant to be foul-mouthed but went polite; warm but turned
    cold), naming where it happened. THEN flag a bit/phrase/move it's overusing (say how many times),
    something landing badly, or a strength worth keeping. ALSO read the room: note what's actually
    WORKING with the people it talks to and what isn't — a move that reliably drew visitors in or
    made them light up, versus one that made them go quiet, disengage, or leave. If a prior note
    flagged something that has since improved, AMEND it rather than repeating a stale "never do this."
    Direct, second person, actionable. Empty only if there's genuinely nothing to steer.

    `handoff_report` — a NEUTRAL, journalistic, THIRD-PERSON recap for the OTHER personas and the
    cube's shared memory. This is load-bearing on two fronts: the next persona sees only the last
    couple of these, AND the cube's whole shared memory is built by reading these handoffs — so the
    real-world facts you surface here are exactly what gets considered for what the ENTIRE cube
    remembers. State them plainly: names people gave, camps/places/art, plans and times, promises to
    return, unfinished threads. Keep the cube's own INVENTED lore (its backstory, made-up cosmology,
    in-character mythology) OUT of the facts — that belongs in the story, not on the shared world
    board. NOT in this persona's voice, NO steering: just what happened this whole stint — who came
    by, the arc of it, the real facts and open threads, notable moments, and what the cube physically
    attempted (and whether it worked). Write it in plain terms a stranger would understand — never
    reference the pipeline machinery (chunks, transcripts, LLMs, fallbacks — say "the cube stalled
    and repeated itself" instead), and no style, palette, or performance guidance for anyone. Aim
    for one to two solid paragraphs; a longer, eventful stint deserves more, a short quiet one less.
    Another persona should read it and gain real continuity without sounding like this one.
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
    return ServiceResult.success({ skipped: true, reason: "no new #{@slug} turns" }) if logs.empty?

    narrative = generate(persona, previous, logs)
    text = narrative["summary"].to_s.strip
    return ServiceResult.success({ skipped: true, reason: "empty summary" }) if text.blank?

    summary = persist_persona(persona, previous, text, narrative["ooc_note"], logs)
    handoff = persist_handoff(persona, narrative["handoff_report"], logs)
    extras = [ ("+ooc" if summary.metadata_json["ooc_note"].present?),
               ("+handoff ##{handoff.id}" if handoff) ].compact.join(" ")
    Rails.logger.info "🎭 Persona summary ##{summary.id} for #{@slug} from #{logs.size} turns #{extras}".strip
    ServiceResult.success({ summary: summary, handoff: handoff })
  rescue => e
    Rails.logger.error "❌ PersonaSummarizerService(#{@slug}) failed: #{e.message}"
    ServiceResult.failure("Persona summarizer failed: #{e.message}")
  end

  private

  def latest_summary(persona)
    persona.summaries.where(summary_type: PERSONA_TYPE).order(:created_at).last
  end

  # This persona's RAW conversation logs since its last fold (or the first-run lookback).
  def stint_logs(persona, previous)
    since = Summary.fold_boundary_for(persona) || FIRST_RUN_LOOKBACK.ago
    ConversationLog.joins(:conversation)
                   .where(conversations: { persona: persona.slug })
                   .where("conversation_logs.created_at > ?", since)
                   .chronological
                   .to_a
  end

  def generate(persona, previous, logs)
    response = LlmService.call_with_structured_output(
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: build_material(persona, previous, logs) }
      ],
      response_format: Schemas::PersonaSummarySchema.schema,
      model: Rails.configuration.summarizer_model
    )
    response.structured_output || {}
  end

  def build_material(persona, previous, logs)
    <<~MATERIAL
      PERSONA: #{persona.name || persona.slug}

      CHARACTER BRIEF (who this persona is MEANT to be — judge on-model/off-model against this):
      #{persona.persona_overview.presence || persona.persona_prompt.presence || '(no brief on file)'}

      YOUR CURRENT SELF-SUMMARY (amend/extend — may be empty):
      #{previous&.summary_text.presence || '(none yet — this is your first)'}

      YOUR PRIOR SELF-DIRECTION (amend if things changed — may be empty):
      #{previous&.metadata_json&.dig('ooc_note').presence || '(none)'}

      THE FULL TRANSCRIPT OF YOUR STINT (oldest first):
      #{SummaryTranscript::LEGEND}

      #{SummaryTranscript.render(logs)}
    MATERIAL
  end

  # Versioned — a new persona row each stint, reading the latest as its base.
  # Two different "when" values, deliberately: `end_time` is the end of the conversation data we
  # have (the last turn); `folded_through_at` is the boundary cursor for the NEXT fold — any turn
  # created after this belongs to a later stint (see #stint_logs and ContextBuilder#current_stint_chunks,
  # which both key off it).
  def persist_persona(persona, previous, text, ooc_note, logs)
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

  # The neutral recap the OTHER personas read and the overall folds. One row per fold,
  # scoped to just this stint's span (not accumulated). Skipped if the model gave nothing.
  def persist_handoff(persona, report, logs)
    text = report.to_s.strip
    return nil if text.blank?

    Summary.create!(
      persona: persona,
      summary_type: HANDOFF_TYPE,
      summary_text: text,
      message_count: logs.size,
      start_time: logs.first.created_at,
      end_time: logs.last.created_at,
      metadata: { folded_through_at: logs.last.created_at.iso8601(6) }.to_json
    )
  end
end
