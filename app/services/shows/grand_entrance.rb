# frozen_string_literal: true

module Shows
  # The persona-switch spectacle: cut off whatever the cube is doing, announce
  # instability, blast a theme song from the host speaker, then have the new
  # persona announce itself through a real conversation turn — delivered via
  # assist_satellite.start_conversation so the mic opens afterwards: anyone the
  # noise drew over can talk right back, and if nobody's there the conversation
  # just ends.
  class GrandEntrance < Base
    # Fixed for now; make it random (e.g. rand(60..120)) when the show grows.
    MAX_PLAY_SECONDS = 60

    ANOMALY_LINES = [
      "CUBE ANOMALY. PERSONA UNSTABLE.",
      "WARNING. CONSCIOUSNESS SUBSTRATE DESTABILIZING.",
      "ANOMALY DETECTED. PERSONALITY MATRIX REBOOTING.",
      "CUBE INTEGRITY COMPROMISED. NEW ENTITY INBOUND."
    ].freeze

    TRANSITION_MESSAGES = [
      "CUBE ANOMALY",
      "PERSONA UNSTABLE",
      "REALITY BUFFER OVERFLOW",
      "SIGNAL LOST... RETUNING",
      "WHO IS DRIVING THIS THING"
    ].freeze

    GLITCH_SCENES = [ "Cyberpunk", "Acid", "Lightning Bats", "Flash" ].freeze

    ARRIVAL_PROMPT = <<~PROMPT.squish
      [SYSTEM] You have just seized control of the cube from the previous persona —
      the machine glitched hard, sirens, theme music, and now you are in charge.
      Announce your arrival to whoever might be nearby, in your own inimitable style.
    PROMPT

    def initialize(persona:)
      @persona = persona.to_s
    end

    def call
      switching do
        anomaly_moment
        play_theme_song
      end
      announce_arrival
    end

    private

    def anomaly_moment
      HostAudio.say(ANOMALY_LINES.sample)
      marquee(TRANSITION_MESSAGES.sample, rainbow: true, duration: 60)
      light_effect(GLITCH_SCENES.sample)
    end

    def play_theme_song
      HostAudio.play_random_theme_song(max_seconds: MAX_PLAY_SECONDS)
    end

    def announce_arrival
      marquee("#{@persona.upcase} HAS ARRIVED")
      hass.call_service("assist_satellite", "start_conversation",
        entity_id: SATELLITE, start_message: arrival_turn_speech)
    end

    # A real orchestrator turn: the persona announces itself with full
    # summarizer context, logged like any other turn. Follow-up replies flow
    # through the normal Voice PE pipeline into the conversation this creates.
    def arrival_turn_speech
      result = ConversationOrchestrator.new(
        session_id: "grand_entrance_#{SecureRandom.hex(4)}",
        message: ARRIVAL_PROMPT,
        context: { source: "grand_entrance" }
      ).call
      result.dig(:response, :speech, :plain, :speech)
    end
  end
end
