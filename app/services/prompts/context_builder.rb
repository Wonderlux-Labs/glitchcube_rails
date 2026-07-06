# app/services/prompts/context_builder.rb
#
# Builds the "# CURRENT CONTEXT" block injected into the system prompt each turn.
# A small, bounded, layered memory (each blob capped):
#
#   1. Ambient world state — the HASS composite sensor (time, weather, …).
#   2. Overall memory      — the latest `overall` summary: the shared in-world story of the
#                            whole event, plus any pending visitor threads and the current
#                            cross-persona director note (steering every persona reads).
#   3. Persona memory      — the CURRENT persona's latest `persona` summary + its
#                            explicit self-steering note (injected so it self-corrects).
#   4. Running memory      — the latest `interaction` summary + real-world facts (may be
#                            from a different persona after a switch — that's fine).
#
# Most turns don't need any of this, but when present it's what gives the cube continuity.
module Prompts
  class ContextBuilder
    WORLD_STATE_SENSOR = "sensor.glitchcube_world_state"
    MAX_BLOB = 900 # truncation backstop so no single memory blob can bloat the prompt

    def self.build(persona: nil)
      new(persona: persona).build
    end

    def initialize(persona: nil)
      @persona = persona&.to_s
    end

    def build
      [
        world_state_context,
        overall_summary_context,
        persona_summary_context,
        recent_summary_context
      ].compact.join("\n\n")
    end

    private

    def world_state_context
      content = HomeAssistantService.entity(WORLD_STATE_SENSOR)&.dig("attributes", "content")
      return nil if content.blank?

      "Right now: #{content.squish}"
    rescue => e
      warn_nil("#{WORLD_STATE_SENSOR}", e)
    end

    def overall_summary_context
      overall = Summary.by_type("overall").recent.first
      return nil if overall&.summary_text.blank?

      meta = overall.metadata_json
      parts = [ "The bigger picture (how this whole event has gone so far): #{clip(overall.summary_text)}" ]

      threads = meta["active_threads"]
      parts << "Still in the air (things visitors set up that you can pick up): #{clip(threads)}" if threads.present?

      director = meta["director_note"]
      parts << "A note to all of the cube's personas right now: #{clip(director)}" if director.present?

      parts.join("\n")
    rescue => e
      warn_nil("overall summary", e)
    end

    def persona_summary_context
      persona = @persona.present? && Persona[@persona]
      return nil unless persona

      summary = persona.summaries.where(summary_type: "persona").order(:created_at).last
      return nil if summary&.summary_text.blank?

      parts = [ "What you (#{persona.name || @persona}) remember from your recent time on the cube: #{clip(summary.summary_text)}" ]
      note = summary.metadata_json["ooc_note"]
      parts << "A note to yourself: #{clip(note)}" if note.present?
      parts.join("\n")
    rescue => e
      warn_nil("persona summary", e)
    end

    def recent_summary_context
      summary = Summary.by_type("interaction").recent.first
      return nil if summary&.summary_text.blank?

      parts = [ "Recently (your running memory of the last little while): #{clip(summary.summary_text)}" ]
      facts = summary.metadata_json["real_world_facts"]
      parts << "Things you've picked up about tonight: #{clip(facts)}" if facts.present?
      parts.join("\n")
    rescue => e
      warn_nil("recent summary", e)
    end

    def clip(text)
      text.to_s.squish.truncate(MAX_BLOB)
    end

    def warn_nil(what, error)
      Rails.logger.warn "⚠️ Could not load #{what} for context: #{error.message}"
      nil
    end
  end
end
