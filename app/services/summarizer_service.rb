# frozen_string_literal: true

# Per-persona interaction summarizer. Writes a short, FACTUAL "chunk" of the current
# persona's stint. Triggered every ~N turns by SummaryTriggers (not on a timer) and flushed
# once more when a persona hands off (from PersonaSummarizerService). Each chunk is scoped to
# ONE persona's conversations — never cross-persona — and carries no steering: performance
# notes live in the persona summary, system-wide notes in the overall. See docs/conversation_flow.md.
class SummarizerService
  MODEL = "google/gemini-3.5-flash"
  SUMMARY_TYPE = "interaction"

  # On the very first run for a persona (no prior chunk) look back this far for material.
  FIRST_RUN_LOOKBACK = 1.hour

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are the running memory of the GlitchCube — an interactive AI art installation that
    talks to festival-goers through a rotating cast of personas (Buddy, Jax, Zorp, and others).
    Right now ONE persona is on the cube, and you are writing a short factual note about the
    latest chunk of its conversations so the cube keeps continuity as its stint goes on.

    This note is FACTUAL, not a critique. Do NOT judge how well the persona is performing, and
    do NOT write in character — that happens elsewhere. Produce three separate things:

    `summary` — ~50-120 words, plainly: what just happened, who came by, the gist of the
    conversations, and what the cube physically ATTEMPTED (lights, music, marquee) and whether
    it seemed to land. Just enough for a later reader to know what went on this chunk.

    `real_world_facts` — concrete true-about-the-world things the cube learned that would matter
    in later conversations: names people gave, plans/events they mention (a party at the Corral
    at 2am, the burn at midnight), camps, places, art around the event. Just the facts, brief.
    Leave empty if nothing concrete came up.

    `active_threads` — unfinished business a REAL VISITOR set up that a later turn or persona
    could pick up: a named person who said they'd be back, a plan, a promise, somewhere they
    were headed. Only what visitors actually said — not lore the cube invented. Empty if none.
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

    previous = latest_chunk(persona)
    logs = logs_since(persona, previous)
    return ServiceResult.success({ skipped: true, reason: "no new interactions" }) if logs.empty?

    narrative = generate(logs, previous)
    summary_text = narrative["summary"].to_s.strip
    return ServiceResult.success({ skipped: true, reason: "empty summary" }) if summary_text.blank?

    summary = persist(persona, summary_text, narrative, logs)
    extras = [ ("+facts" if summary.metadata_json["real_world_facts"].present?),
               ("+threads" if summary.metadata_json["active_threads"].present?) ].compact.join(" ")
    Rails.logger.info "📝 Interaction chunk ##{summary.id} for #{@slug} from #{logs.size} turns #{extras}".strip
    ServiceResult.success({ summary: summary })
  rescue => e
    Rails.logger.error "❌ SummarizerService(#{@slug}) failed: #{e.message}"
    ServiceResult.failure("Summarizer failed: #{e.message}")
  end

  private

  def latest_chunk(persona)
    Summary.interaction.where(persona_id: persona.id).recent.first
  end

  # This persona's conversation logs since its last chunk was written.
  def logs_since(persona, previous)
    since = previous&.end_time || FIRST_RUN_LOOKBACK.ago
    ConversationLog.joins(:conversation)
                   .where(conversations: { persona: persona.slug })
                   .where("conversation_logs.created_at > ?", since)
                   .chronological
                   .to_a
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
      PREVIOUS CHUNK (for continuity — may be empty):
      #{previous&.summary_text.presence || '(none yet — this is the first chunk this stint)'}

      RECENT INTERACTIONS (oldest first):
      #{SummaryTranscript::LEGEND}

      #{SummaryTranscript.render(logs)}
    MATERIAL
  end

  def persist(persona, summary_text, narrative, logs)
    Summary.create!(
      persona: persona,
      summary_type: SUMMARY_TYPE,
      summary_text: summary_text,
      message_count: logs.size,
      start_time: logs.first.created_at,
      end_time: logs.last.created_at,
      metadata: {
        real_world_facts: narrative["real_world_facts"].presence,
        active_threads: narrative["active_threads"].presence
      }.compact.to_json
    )
  end
end
