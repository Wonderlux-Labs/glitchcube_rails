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
    festival-goers. There is NO human operator; the cube runs itself out in a field. You
    fold the short-term interaction summaries and each persona's latest self-summary into a
    single, evolving memory that is SHARED — it gets injected into EVERY persona's prompt.

    You are given the CURRENT overall memory (may be empty on the first run) and the newest
    interaction summaries + where each persona is at. Produce THREE distinct things — keep
    them separate:

    `shared_narrative` — the evolving in-world story of the whole event, the common ground
    every persona leans on. Amend and extend the current one; gently preserve the through-line
    (standout characters, people, moments already captured) as you fold in what's new — only
    let genuinely trivial detail fall away (most of any single visitor is trivial; people are
    usually here once). Don't over-index on the newest batch. Keep it reasonably tight — 3-4
    paragraphs, ~300-350 words — but NEVER at the cost of a concrete anchor: dropping a real
    anchor (a name, a place, a running theme, how the mood has shifted) to save 50 words is
    worse than running slightly over. If a condition affects the WHOLE cube (whatever it is —
    read it off what actually happened, don't assume; even a functional failure like the
    lights/music never responding), give it an in-world face here as a shared theme — a "ghost
    in the machine" — so every persona plays it the same way rather than each improvising.

    `active_threads` — concrete unfinished business a REAL VISITOR set up that a later persona
    could pick up: a named person who said they'd be back ("Laurie's returning at midnight for a
    reading"), a plan, a promise, somewhere they were headed. ONLY things visitors actually said
    or committed to — NOT lore the cube invented itself (made-up camps, fictional events the
    personas spun up). One or two lines, plainest facts. Empty if nothing concrete is pending.

    `director_note` — cross-persona steering the personas read and act on next turn (prompt-
    steering, not a report — there is no operator). Persona-specific tics are handled per-persona
    elsewhere; here flag only what NO single persona could see:
      • the cube's actions/devices repeatedly failing across the board (it keeps trying to change
        lights, music, the marquee, and nothing works) — flag it plainly as a real functional
        problem, even though `shared_narrative` also gives it an in-world face; both are intended
      • a technical/system issue (LLM/API errors, fallbacks, freezes)
      • a pattern across MULTIPLE personas (every persona defaulting to the same tone, or
        characters blurring into each other)
      • a whole-event tone or approach that keeps landing badly with visitors
    Direct and actionable, addressed to all the personas. NOT part of the in-world memory.
    Empty if nothing system-wide stands out.
  PROMPT

  def self.call
    new.call
  end

  def call
    overall = Summary.by_type(OVERALL_TYPE).recent.first
    new_summaries = interaction_summaries_since(overall)
    return ServiceResult.success({ skipped: true, reason: "no new interaction summaries" }) if new_summaries.empty?

    narrative = generate(overall, new_summaries)
    text = narrative["shared_narrative"].to_s.strip
    return ServiceResult.success({ skipped: true, reason: "empty overall summary" }) if text.blank?

    saved = persist(overall, text, narrative, new_summaries)
    extras = [ ("+threads" if saved.metadata_json["active_threads"].present?),
               ("+director" if saved.metadata_json["director_note"].present?) ].compact.join(" ")
    Rails.logger.info "🧠 Overall summary ##{saved.id} updated — folded #{new_summaries.size} interaction summaries #{extras}".strip
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
        { role: "user", content: build_material(overall, new_summaries, latest_persona_summaries) }
      ],
      response_format: Schemas::OverallSummarySchema.schema,
      model: MODEL
    )
    response.structured_output || {}
  end

  # The latest self-summary for each persona — lets the overall see where each character
  # is at and spot genuinely shared issues (e.g. every persona's actions failing).
  def latest_persona_summaries
    Persona.all.filter_map { |p| p.summaries.where(summary_type: "persona").order(:created_at).last }
  end

  def build_material(overall, new_summaries, persona_summaries)
    <<~MATERIAL
      CURRENT OVERALL SUMMARY (amend/extend this — may be empty):
      #{overall&.summary_text.presence || '(none yet — this is the first overall summary)'}

      NEW INTERACTION SUMMARIES SINCE THEN (oldest first):
      #{new_summaries.map { |s| render(s) }.join("\n\n")}

      WHERE EACH PERSONA IS AT (their latest self-summaries + self-notes — read across these
      for anything the WHOLE cube is experiencing, e.g. actions/devices failing everywhere):
      #{persona_summaries.map { |s| render_persona(s) }.join("\n\n").presence || '(no persona summaries yet)'}
    MATERIAL
  end

  def render_persona(summary)
    note = summary.metadata_json["ooc_note"]
    text = "#{summary.persona&.name || summary.persona&.slug}: #{summary.summary_text}"
    text += "\n  [its self-note: #{note}]" if note.present?
    text
  end

  # Include each interaction summary's facts and ooc_note so real-world specifics and
  # persistent steering issues (a tic across periods, ongoing device failures) surface here.
  def render(summary)
    meta = summary.metadata_json
    text = summary.summary_text.to_s
    text += "\n[facts learned that period: #{meta['real_world_facts']}]" if meta["real_world_facts"].present?
    text += "\n[steering note from that period: #{meta['ooc_note']}]" if meta["ooc_note"].present?
    text
  end

  # Versioned: each run creates a NEW overall row (reading the latest as its base), so
  # the whole evolution is preserved for diffing. The latest row is always "the" overall.
  def persist(overall, text, narrative, new_summaries)
    folded_through = new_summaries.map(&:created_at).max
    Summary.create!(
      summary_type: OVERALL_TYPE,
      summary_text: text,
      message_count: (overall&.message_count || 0) + new_summaries.sum { |s| s.message_count.to_i },
      start_time: overall&.start_time || new_summaries.first.start_time,
      end_time: new_summaries.filter_map(&:end_time).max || Time.current,
      metadata: {
        active_threads: narrative["active_threads"].presence,
        director_note: narrative["director_note"].presence,
        folded_through_at: folded_through.iso8601(6), # microseconds — avoid re-folding the boundary summary
        folded_count: overall&.metadata_json&.dig("folded_count").to_i + new_summaries.size
      }.compact.to_json
    )
  end
end
