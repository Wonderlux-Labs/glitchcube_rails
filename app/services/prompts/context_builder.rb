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
#                               state, kept second-to-last.
#   6. Camera view            — a short description of what the cube's camera currently sees
#                               (input_text.current_camera_state), closest to the raw message
#                               history. Present only when non-empty; HASS clears it after
#                               ~3 min, so when it's there it's fresh.
#   7. Conversation pacing    — from the 5th round of a conversation on: work toward your
#                               goal or wind it down (and if ending, remind them how to wake
#                               the cube back up, in character).
#   8. Glitch premonition     — only when the random rotation's next persona switch is <5 min
#                               out: a "you feel a glitch coming on — say your goodbyes now"
#                               so the persona can sense its own end and wrap up in character.
#
# Nothing here is char-clipped. Each summarizer's own prompt is responsible for keeping its
# output the right length (handoffs ~2 paragraphs, persona summary ~180 words, chunks ~120
# words, overall ~400 words); truncating mid-sentence at the point of consumption only ever
# hurt the load-bearing handoffs. We bound BREADTH (how many current-session chunks) not DEPTH.
module Prompts
  class ContextBuilder
    WORLD_STATE_SENSOR = "sensor.glitchcube_world_state"
    CAMERA_STATE_ENTITY = "input_text.current_camera_state"
    CURRENT_SESSION_CHUNKS = 4
    PREMONITION_WINDOW = 5.minutes
    WRAP_UP_AFTER_ROUNDS = 5

    # Event framing for the night (Lakes of Fire final night, 2026-07-18). Injected
    # verbatim at the top of the context so every persona knows the situation. Remove
    # (or update) after the event.
    EVENT_NOTE = "Tonight is the last night of the burn, but nothing will burn because " \
                 "of a fire ban. The burn is on brand new land this year and it has been " \
                 "crowded and forest fires have made it smoky as hell, but it has finally " \
                 "cleared up."

    def self.build(persona: nil, conversation: nil)
      new(persona: persona, conversation: conversation).build
    end

    def initialize(persona: nil, conversation: nil)
      @persona = persona&.to_s
      @conversation = conversation
    end

    def build
      [
        event_note_context,
        overall_summary_context,
        recent_history_context,
        persona_summary_context,
        current_session_context,
        world_state_context,
        camera_context,
        conversation_opening_context,
        conversation_pacing_context,
        glitch_premonition_context
      ].compact.join("\n\n")
    end

    private

    # 0. Tonight's event framing — a fixed one-liner every persona should know.
    def event_note_context
      EVENT_NOTE
    end

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

    # 6. The live camera view — its own block, below the ambient world state, closest to the
    #    raw messages. Present only when the input_text is non-empty; when it's blank (or the
    #    HASS clear automation has wiped it) nothing is injected. HASS owns staleness, so a
    #    presence check is all we need here — no timestamps.
    def camera_context
      return nil if Rails.configuration.disable_camera

      desc = HomeAssistantService.entity(CAMERA_STATE_ENTITY)&.dig("state")
      return nil if desc.blank?

      "Right now, your camera shows: #{desc.squish}"
    rescue => e
      warn_nil(CAMERA_STATE_ENTITY, e)
    end

    # 6b. On the very first turn of a fresh conversation (round 1), have the persona close
    #     out its opening reply by teaching the visitor the wake word — so if the "connection
    #     gets glitchy" and the cube drops them, they know how to come back. Round == 1 only,
    #     so it never repeats within the same conversation.
    def conversation_opening_context
      return nil unless @conversation

      round = @conversation.conversation_logs.count + 1
      return nil unless round == 1

      "This is the very FIRST thing you're saying to this visitor. End this opening reply, in " \
      "your own voice and in character, by letting them know that if the connection gets glitchy " \
      "and you drop out on them, they can always wake you back up by saying \"Hey Glitch Cube\". " \
      "Work it in naturally as a sign-off — don't recite it like a disclaimer."
    rescue => e
      warn_nil("conversation opening", e)
    end

    # 7. From the 5th round of a conversation on, nudge the persona to work toward its
    #    goal or wind the conversation down instead of chatting forever. Round = which
    #    reply we're about to generate (logs persist at turn end, so count + 1).
    def conversation_pacing_context
      return nil unless @conversation

      round = @conversation.conversation_logs.count + 1
      return nil if round < WRAP_UP_AFTER_ROUNDS

      "You're #{round} rounds into this conversation now. Don't let it drift on forever: " \
      "be working toward what you actually want out of it (your goals), or find a natural, " \
      "in-character way to bring it to a close. If you do end it — set continue_conversation " \
      "to false — make sure you remind them, in your own voice and in character, that they " \
      "can wake you back up by saying \"Hey Glitch Cube\" if they want to keep talking."
    rescue => e
      warn_nil("conversation pacing", e)
    end

    # 8. When the random rotation (Recurring::Persona::RandomPersonaJob) is about to
    #    switch personas, let the current one feel it coming. A past-due timestamp
    #    also counts — the job's next 5-min tick will fire the switch any moment.
    #    Purely flavor; the persona may or may not reference it.
    def glitch_premonition_context
      next_at = Rails.cache.read(Recurring::Persona::RandomPersonaJob::NEXT_SWITCH_KEY)
      return nil if next_at.blank?
      return nil if Time.parse(next_at.to_s) > PREMONITION_WINDOW.from_now

      "You feel a glitch coming on. The cube is getting unstable — you can sense that someone " \
      "else is about to take over, any moment now. If you're mid-conversation, THIS is the " \
      "moment to say your goodbyes and wrap things up in your own voice before you glitch out — " \
      "you won't get a clean chance once the takeover hits."
    rescue => e
      warn_nil("glitch premonition", e)
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
