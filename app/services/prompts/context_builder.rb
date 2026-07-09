# app/services/prompts/context_builder.rb
#
# Builds the "# CURRENT CONTEXT" block injected into the system prompt each turn.
# Ordered broad → specific → live, so the model reads background before foreground:
#
#   1. The bigger picture     — the latest structural `overall` digest (world board of durable
#                               facts, recurring visitors, threads, optional director note).
#   2. The cube's recent      — the last 2 neutral `handoff` reports (what other personas just
#      history                   did), persona-labeled with their Eastern-time ranges.
#   3. Your own past          — the CURRENT persona's latest `persona` summary + self-steering.
#   4. Your current session   — this persona's current-stint interaction chunks (since it woke).
#   5. Live now               — the HASS composite sensor (time, weather); the most volatile
#                               state, kept LAST, closest to the raw message history that follows.
#
# Nothing here is char-clipped. Each summarizer's own prompt is responsible for keeping its
# output the right length (handoffs ~2 paragraphs, persona summary ~180 words, chunks ~120
# words, overall ~400 words); truncating mid-sentence at the point of consumption only ever
# hurt the load-bearing handoffs. We bound BREADTH (how many current-session chunks) not DEPTH.
module Prompts
  class ContextBuilder
    WORLD_STATE_SENSOR = "sensor.glitchcube_world_state"
    CURRENT_SESSION_CHUNKS = 4

    def self.build(persona: nil)
      new(persona: persona).build
    end

    def initialize(persona: nil)
      @persona = persona&.to_s
    end

    def build
      [
        overall_summary_context,
        recent_history_context,
        persona_summary_context,
        current_session_context,
        world_state_context
      ].compact.join("\n\n")
    end

    private

    # 1. The structural digest — rendered as a scannable "world board". Not clipped.
    def overall_summary_context
      overall = Summary.by_type("overall").recent.first
      return nil if overall&.summary_text.blank?

      meta = overall.metadata_json
      parts = [ "## The bigger picture", overall.summary_text.to_s.strip ]
      section(parts, "Durable places / camps / event facts", meta["durable_facts"])
      section(parts, "Recurring visitors", meta["recurring_visitors"])
      section(parts, "Still in the air", meta["active_threads"])
      section(parts, "A note to all of the cube's personas right now", meta["director_note"])
      parts.join("\n")
    rescue => e
      warn_nil("overall summary", e)
    end

    # 2. The last two handoffs — neutral, so the current persona doesn't inherit another's voice.
    def recent_history_context
      handoffs = Summary.by_type("handoff").recent.limit(2).to_a
      return nil if handoffs.empty?

      lines = [ "The cube's recent history (what happened on the cube just before you woke up):" ]
      handoffs.reverse_each { |h| lines << "• #{SummaryRenderer.handoff(h)}" } # oldest of the two first
      lines.join("\n")
    rescue => e
      warn_nil("recent history", e)
    end

    # 3. This persona's own evolving memory + self-steering note.
    def persona_summary_context
      persona = @persona.present? && Persona[@persona]
      return nil unless persona

      summary = persona.summaries.where(summary_type: "persona").order(:created_at).last
      return nil if summary&.summary_text.blank?

      parts = [ "What you (#{persona.name || @persona}) remember from your recent time on the cube: #{summary.summary_text.to_s.strip}" ]
      note = summary.metadata_json["ooc_note"]
      parts << "A note to yourself: #{note.to_s.strip}" if note.present?
      parts.join("\n")
    rescue => e
      warn_nil("persona summary", e)
    end

    # 4. The current stint's interaction chunks (since this persona's last fold).
    def current_session_context
      persona = @persona.present? && Persona[@persona]
      return nil unless persona

      chunks = current_stint_chunks(persona)
      return nil if chunks.empty?

      lines = [ "Your current session so far (what's happened since you woke up this time):" ]
      chunks.each { |c| lines << SummaryRenderer.interaction_chunk(c) }
      lines.join("\n\n")
    rescue => e
      warn_nil("current session", e)
    end

    # 5. Ambient live state — kept last, closest to the raw message history.
    def world_state_context
      content = HomeAssistantService.entity(WORLD_STATE_SENSOR)&.dig("attributes", "content")
      return nil if content.blank?

      "Right now: #{content.squish}"
    rescue => e
      warn_nil("#{WORLD_STATE_SENSOR}", e)
    end

    def current_stint_chunks(persona)
      # Boundary is the last fold's `folded_through_at` cursor — the same cursor the persona
      # summarizer uses, so "current session" is exactly the chunks not yet folded into a summary.
      since = Summary.fold_boundary_for(persona)
      scope = Summary.interaction.where(persona_id: persona.id)
      scope = scope.where("created_at > ?", since) if since
      scope.order(:start_time).last(CURRENT_SESSION_CHUNKS)
    end

    def section(parts, heading, body)
      return if body.blank?

      parts << "\n## #{heading}"
      parts << body.to_s.strip
    end

    def warn_nil(what, error)
      Rails.logger.warn "⚠️ Could not load #{what} for context: #{error.message}"
      nil
    end
  end
end
