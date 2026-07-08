# frozen_string_literal: true

# Rolling interaction summarizer. Runs every ~10 minutes (Recurring::Memory::SummarizerJob):
# reads the conversation turns since the last summary, makes ONE structured LLM call,
# and writes a short "running memory" Summary row (type `interaction`) plus an optional
# out-of-character operator note. Only the single most recent prior summary is fed in
# for continuity — deliberately light. See docs/conversation_flow.md.
class SummarizerService
  MODEL = "google/gemini-3.5-flash"
  SUMMARY_TYPE = "interaction"

  # On the very first run (no prior summary) look back this far for material.
  FIRST_RUN_LOOKBACK = 1.hour

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are the running memory of the GlitchCube — an interactive AI art installation
    that talks to festival-goers through a rotating cast of personas (Buddy, Jax, Zorp,
    and others). Every ~10 minutes you read the most recent interactions and update the
    cube's short-term memory so it keeps a sense of continuity between conversations,
    even as personas and visitors change. (The cube knows it is one cube wearing many
    personas, so shifts between them are fine — note who was on if it matters.)

    You produce THREE separate things. Keep them distinct:

    `summary` — a short, honest, in-world account of what these interactions were actually
    like: who came by, the vibe and how it's shifting, how the conversations are going,
    anything memorable worth carrying forward. Write it naturally, the way the cube would
    remember its night — not a checklist. A paragraph or two; a sentence is fine if little
    happened. This gets injected back into the cube's memory as in-world narrative, so keep it
    in-world: anything about how a persona is PERFORMING (a tic, drift, device trouble, what to
    adjust) belongs in `ooc_note`, never here.

    `real_world_facts` — concrete, true-about-the-world things the cube learned that would
    matter in later conversations: names people gave, plans and events they mention (a party
    at the Corral later, the burn at midnight), what's happening around the event, camps,
    places, art. Just the facts, brief. Leave empty if nothing concrete came up. (Pulling
    these out separately from the story tends to surface the useful specifics.)

    `ooc_note` — a note to the cube's own future self / the personas (there is no human
    operator — this is prompt-steering the LLMs read directly). The ONLY place for steering.
    Flag things like:
      • how visitors seem to be RESPONDING — delighted and engaged, or bored, confused,
        annoyed, or drifting off. If a move keeps landing WELL, note to keep leaning on it;
        if visitors repeatedly react the same negative way, that's a strong signal to adjust
      • the cube repeatedly trying to change the lights/music/marquee and getting nothing
        back — if that's clearly happening in the interactions, note it (don't assume it;
        read it off what actually occurred)
      • a tic, loop, or catchphrase a persona overuses; characters slipping or blurring
      • a move that keeps landing badly, or anyone who seemed genuinely distressed
    Direct and actionable ("You keep… — ease off it"). NOT part of the story. Only write a note
    when something genuinely actionable emerged; otherwise leave it empty.
  PROMPT

  def self.call
    new.call
  end

  def call
    previous = Summary.by_type(SUMMARY_TYPE).recent.first
    logs = logs_since(previous)
    return ServiceResult.success({ skipped: true, reason: "no new interactions" }) if logs.empty?

    narrative = generate(logs, previous)
    summary_text = narrative["summary"].to_s.strip
    return ServiceResult.success({ skipped: true, reason: "empty summary" }) if summary_text.blank?

    summary = persist(summary_text, narrative, logs)
    extras = [ ("+facts" if summary.metadata_json["real_world_facts"].present?),
               ("+ooc" if summary.metadata_json["ooc_note"].present?) ].compact.join(" ")
    Rails.logger.info "📝 Summary ##{summary.id} written from #{logs.size} turns #{extras}".strip
    ServiceResult.success({ summary: summary })
  rescue => e
    Rails.logger.error "❌ SummarizerService failed: #{e.message}"
    ServiceResult.failure("Summarizer failed: #{e.message}")
  end

  private

  def logs_since(previous)
    since = previous&.end_time || FIRST_RUN_LOOKBACK.ago
    ConversationLog.where("created_at > ?", since).chronological.to_a
  end

  def generate(logs, previous)
    response = LlmService.call_with_structured_output(
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: build_material(logs, previous) }
      ],
      response_format: Schemas::SummarySchema.schema,
      model: MODEL
    )
    response.structured_output || {}
  end

  def build_material(logs, previous)
    <<~MATERIAL
      PREVIOUS RUNNING MEMORY (for continuity — may be empty):
      #{previous&.summary_text.presence || '(none yet — this is the first summary)'}

      RECENT INTERACTIONS (oldest first):
      #{SummaryTranscript::LEGEND}

      #{SummaryTranscript.render(logs)}
    MATERIAL
  end

  def persist(summary_text, narrative, logs)
    Summary.create!(
      summary_type: SUMMARY_TYPE,
      summary_text: summary_text,
      message_count: logs.size,
      start_time: logs.first.created_at,
      end_time: logs.last.created_at,
      metadata: {
        real_world_facts: narrative["real_world_facts"].presence,
        ooc_note: narrative["ooc_note"].presence
      }.compact.to_json
    )
  end
end
