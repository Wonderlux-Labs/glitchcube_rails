# frozen_string_literal: true

# The cube's durable long-term digest. Folds the neutral persona HANDOFF reports into a
# SINGLE evolving `overall` summary — the structural, shared memory injected into every
# persona's prompt (a "world board" of durable facts + recurring visitors + threads, plus an
# OPTIONAL cross-persona director note only when a whole-cube pattern emerges). Reads ONLY
# handoffs (each handoff already distilled a persona's stint), not raw interactions or persona
# self-summaries. Runs periodically (Recurring::Memory::OverallSummarizerJob) and can be
# triggered manually.
class OverallSummarizerService
  OVERALL_TYPE = "overall"
  HANDOFF_TYPE = "handoff"

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are the LONG-TERM memory of the GlitchCube — an interactive art installation whose
    rotating personas (Buddy, Jax, Zorp, and others) talk to festival-goers out in a field with
    NO human operator. You are given the CURRENT WORLD BOARD (your existing memory — may be empty)
    and the newest HANDOFF reports — neutral, journalistic recaps each persona left when its stint
    ended. Roll the world board FORWARD into a single, evolving, SHARED memory injected into EVERY
    persona's prompt.

    You are REBUILDING each field, not appending: for every field, produce an updated version that
    carries forward what still matters from the current world board, folds in the new handoffs, and
    DROPS what's gone stale. This keeps memory durable (a fact from an hour ago survives even if the
    latest handoff didn't mention it) without letting it sprawl. Carry forward FACTS, never prose:
    rewrite every field fresh in your own words each run instead of copying the previous board's
    sentences or phrasing. If grandiose language is accumulating ("legendary", "has cemented
    itself"), flatten it back to plain reporting.

    Produce these fields — keep them distinct:

    `shared_narrative` — the structural story of the event so far, the common ground every persona
    leans on. Grounded, not flowery. Keep durable anchors, fold in the new handoffs, and roll
    up/compress older detail as the night grows. Aim for 3-4 tight paragraphs (~400 words) — if
    you're past that, compress older material. If something affects the WHOLE cube (even a
    functional failure like devices never responding), give it an in-world face here so every
    persona plays it the same way.

    `durable_facts` — the "world board": places, camps, events visitors keep mentioning that stay
    true across the night (a camp's rumored event, a quiet lounge, a loud sound camp — format
    illustrations only, never write them onto the board). Short lines. ONLY facts that actually
    surfaced in the handoffs — never placeholder or "not yet known" lines, and the cube's own mood,
    performance, or capabilities are not world facts (those live in the narrative, if anywhere).
    Carry forward the still-relevant ones, add new, drop stale; keep the ~5-8 most relevant. This
    is what makes the cube feel like it's actually AT this event. Empty if nothing durable surfaced.

    `recurring_visitors` — named anchors: people who gave a name and left a hook ("Marco: wants a
    deep lavender-purple glow, may be back by sunrise"). Short lines. Carry forward, add new, rotate
    out anyone not mentioned lately; keep the ~5 most relevant. Empty if none.

    `active_threads` — concrete unfinished business a REAL VISITOR set up a later persona could
    pick up. Only what visitors actually said — not invented lore. Carry forward open threads, add
    new, drop resolved or clearly-expired ones. Empty if nothing is pending.

    `director_note` — OPTIONAL. Leave empty unless a genuine WHOLE-CUBE pattern jumps out across
    the handoffs (devices failing every stint, all personas blurring, a whole-event approach
    landing badly). Corrective, not creative: flag a problem or pattern to fix — never direct all
    personas to adopt one persona's bit, style, or storyline, and never assign emotional homework
    ("keep X sacred"). If it's fun rather than broken, leave it empty. Do NOT force one — steering
    mostly lives per-persona.
  PROMPT

  def self.call
    new.call
  end

  def call
    overall = Summary.by_type(OVERALL_TYPE).recent.first
    handoffs = handoffs_since(overall)
    return ServiceResult.success({ skipped: true, reason: "no new handoffs" }) if handoffs.empty?

    narrative = generate(overall, handoffs)
    text = narrative["shared_narrative"].to_s.strip
    return ServiceResult.success({ skipped: true, reason: "empty overall summary" }) if text.blank?

    saved = persist(overall, text, narrative, handoffs)
    extras = [ ("+facts" if saved.metadata_json["durable_facts"].present?),
               ("+visitors" if saved.metadata_json["recurring_visitors"].present?),
               ("+threads" if saved.metadata_json["active_threads"].present?),
               ("+director" if saved.metadata_json["director_note"].present?) ].compact.join(" ")
    Rails.logger.info "🧠 Overall summary ##{saved.id} updated — folded #{handoffs.size} handoffs #{extras}".strip
    ServiceResult.success({ summary: saved, folded: handoffs.size })
  rescue => e
    Rails.logger.error "❌ OverallSummarizerService failed: #{e.message}"
    ServiceResult.failure("Overall summarizer failed: #{e.message}")
  end

  private

  # Handoff reports created after the ones already folded into the overall.
  def handoffs_since(overall)
    through = overall&.metadata_json&.dig("folded_through_at")
    scope = Summary.by_type(HANDOFF_TYPE).order(:created_at)
    scope = scope.where("created_at > ?", Time.zone.parse(through)) if through.present?
    scope.to_a
  end

  def generate(overall, handoffs)
    response = LlmService.call_with_structured_output(
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: build_material(overall, handoffs) }
      ],
      response_format: Schemas::OverallSummarySchema.schema,
      model: Rails.configuration.summarizer_model
    )
    response.structured_output || {}
  end

  def build_material(overall, handoffs)
    <<~MATERIAL
      CURRENT WORLD BOARD — your existing memory. Roll this FORWARD: produce an updated version of
      each field (carry what still matters, fold in the new handoffs, drop what's gone stale). You
      are REPLACING these fields, not appending to them. May be empty on the first run.
      #{render_current(overall)}

      NEW HANDOFF REPORTS SINCE THEN (oldest first — each is one persona's stint, persona-labeled
      with its time range):
      #{handoffs.map { |h| SummaryRenderer.handoff(h) }.join("\n\n")}
    MATERIAL
  end

  # The full current world board (not just the narrative) so the model can carry durable facts,
  # recurring visitors, and open threads forward instead of losing them the moment they drop out
  # of the newest handoffs.
  def render_current(overall)
    return "(none yet — this is the first overall summary)" if overall.nil?

    meta = overall.metadata_json
    parts = [ "Narrative: #{overall.summary_text}" ]
    parts << "Durable facts: #{meta['durable_facts']}" if meta["durable_facts"].present?
    parts << "Recurring visitors: #{meta['recurring_visitors']}" if meta["recurring_visitors"].present?
    parts << "Active threads: #{meta['active_threads']}" if meta["active_threads"].present?
    parts.join("\n")
  end

  # Versioned: each run creates a NEW overall row (reading the latest as its base), so the
  # whole evolution is preserved. The latest row is always "the" overall.
  def persist(overall, text, narrative, handoffs)
    folded_through = handoffs.map(&:created_at).max
    Summary.create!(
      summary_type: OVERALL_TYPE,
      summary_text: text,
      message_count: (overall&.message_count || 0) + handoffs.sum { |h| h.message_count.to_i },
      start_time: overall&.start_time || handoffs.first.start_time,
      end_time: handoffs.filter_map(&:end_time).max || Time.current,
      metadata: {
        durable_facts: narrative["durable_facts"].presence,
        recurring_visitors: narrative["recurring_visitors"].presence,
        active_threads: narrative["active_threads"].presence,
        director_note: narrative["director_note"].presence,
        folded_through_at: folded_through.iso8601(6), # microseconds — avoid re-folding the boundary
        folded_count: overall&.metadata_json&.dig("folded_count").to_i + handoffs.size
      }.compact.to_json
    )
  end
end
