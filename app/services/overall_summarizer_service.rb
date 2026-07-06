# frozen_string_literal: true

# Summary-of-summaries. Folds the rolling `interaction` summaries into a SINGLE
# evolving `overall` summary — the cube's durable long-term memory of the event.
# Also acts as the DIRECTOR: its ooc_note carries system-wide steering (persistent
# acting/repetition/functionality issues) for ALL personas. Runs periodically
# (Recurring::Memory::OverallSummarizerJob) and can be triggered manually.
class OverallSummarizerService
  MODEL = "google/gemini-3.5-flash"
  OVERALL_TYPE = "overall"
  INTERACTION_TYPE = "interaction"

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are the LONG-TERM memory and director of the GlitchCube — an interactive art
    installation whose rotating personas (Buddy, Jax, Zorp, and others) talk to
    festival-goers. Periodically you read the short-term interaction summaries and fold
    them into ONE single, evolving overall summary: the cube's durable sense of how the
    whole event has gone.

    You are given the CURRENT overall summary (may be empty on the first run) and the
    newest interaction summaries since it was last updated. Produce an updated `summary`
    that amends and extends the current one. This is the memory of the WHOLE event, so
    gently preserve the through-line — the standout characters, people, and moments already
    captured — as you fold in what's new; only let genuinely trivial detail fall away (most
    of any single visitor is trivial — people are usually here once). Don't over-index on
    the newest batch, and don't let it sprawl: keep it tight — roughly 2-3 paragraphs and
    comfortably under ~250 words. Preserve the concrete anchors that give real continuity:
    recurring people (names, regulars, anyone who's come back), places / camps / events
    that keep coming up, running themes, and how the overall mood has evolved.

    Separately, you also act as the cube's DIRECTOR at the SYSTEM level. Persona-specific
    steering (one persona overusing a bit) is handled elsewhere — here in `ooc_note` focus
    on [OOC: system functioning + broad, cross-persona notes] that no single interaction or
    single persona could see:
      • the cube's actions/devices repeatedly failing across the board (it keeps trying to
        change lights, music, the marquee, etc. and nothing works) — a real functional
        problem, not in-world flavor
      • a technical/system issue (LLM/API errors, fallbacks, freezes)
      • a pattern showing up across MULTIPLE different personas (e.g. every persona defaulting
        to the same tone, or characters blurring into each other)
      • a whole-event tone or approach that keeps landing badly with visitors
    Direct and actionable, to the operators and to all personas. NOT part of the in-world
    memory. Empty if nothing system-wide stands out.
  PROMPT

  def self.call
    new.call
  end

  def call
    overall = Summary.by_type(OVERALL_TYPE).recent.first
    new_summaries = interaction_summaries_since(overall)
    return ServiceResult.success({ skipped: true, reason: "no new interaction summaries" }) if new_summaries.empty?

    narrative = generate(overall, new_summaries)
    text = narrative["summary"].to_s.strip
    return ServiceResult.success({ skipped: true, reason: "empty overall summary" }) if text.blank?

    saved = persist(overall, text, narrative["ooc_note"], new_summaries)
    Rails.logger.info "🧠 Overall summary ##{saved.id} updated — folded #{new_summaries.size} interaction summaries#{' (+ooc_note)' if saved.metadata_json['ooc_note'].present?}"
    ServiceResult.success({ summary: saved, folded: new_summaries.size })
  rescue => e
    Rails.logger.error "❌ OverallSummarizerService failed: #{e.message}"
    ServiceResult.failure("Overall summarizer failed: #{e.message}")
  end

  private

  # Interaction summaries created after the ones already folded into the overall.
  def interaction_summaries_since(overall)
    through = overall&.metadata_json&.dig("folded_through_at")
    scope = Summary.by_type(INTERACTION_TYPE).order(:created_at)
    scope = scope.where("created_at > ?", Time.zone.parse(through)) if through.present?
    scope.to_a
  end

  def generate(overall, new_summaries)
    response = LlmService.call_with_structured_output(
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: build_material(overall, new_summaries) }
      ],
      response_format: Schemas::OverallSummarySchema.schema,
      model: MODEL
    )
    response.structured_output || {}
  end

  def build_material(overall, new_summaries)
    <<~MATERIAL
      CURRENT OVERALL SUMMARY (amend/extend this — may be empty):
      #{overall&.summary_text.presence || '(none yet — this is the first overall summary)'}

      NEW INTERACTION SUMMARIES SINCE THEN (oldest first):
      #{new_summaries.map { |s| render(s) }.join("\n\n")}
    MATERIAL
  end

  # Include each interaction summary's facts and ooc_note so real-world specifics and
  # persistent steering issues (a tic across periods, ongoing device failures) surface here.
  def render(summary)
    meta = summary.metadata_json
    text = summary.summary_text.to_s
    text += "\n[facts learned that period: #{meta['real_world_facts']}]" if meta["real_world_facts"].present?
    text += "\n[operator note from that period: #{meta['ooc_note']}]" if meta["ooc_note"].present?
    text
  end

  # Versioned: each run creates a NEW overall row (reading the latest as its base), so
  # the whole evolution is preserved for diffing. The latest row is always "the" overall.
  def persist(overall, text, ooc_note, new_summaries)
    folded_through = new_summaries.map(&:created_at).max
    Summary.create!(
      summary_type: OVERALL_TYPE,
      summary_text: text,
      message_count: (overall&.message_count || 0) + new_summaries.sum { |s| s.message_count.to_i },
      start_time: overall&.start_time || new_summaries.first.start_time,
      end_time: new_summaries.filter_map(&:end_time).max || Time.current,
      metadata: {
        ooc_note: ooc_note.presence,
        folded_through_at: folded_through.iso8601(6), # microseconds — avoid re-folding the boundary summary
        folded_count: overall&.metadata_json&.dig("folded_count").to_i + new_summaries.size
      }.compact.to_json
    )
  end
end
