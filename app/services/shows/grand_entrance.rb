# frozen_string_literal: true

module Shows
  # The persona-switch spectacle: cut off whatever the cube is doing, announce
  # instability, blast a theme song from the host speaker, then have the new
  # persona announce itself through a real conversation turn — delivered via
  # assist_satellite.start_conversation so the mic opens afterwards: anyone the
  # noise drew over can talk right back, and if nobody's there the conversation
  # just ends.
  class GrandEntrance < Base
    # Only 45s of the theme song (was 60) so the mic-muted dead-air window stays short.
    MAX_PLAY_SECONDS = 45

    # The voice-assistant media player. We wait for it to stop playing before cutting in,
    # so we don't stomp the outgoing persona's final TTS with sirens and a theme song.
    VOICE_MEDIA_PLAYER = "media_player.cube_cube_voice_media_player"
    SPEECH_WAIT_TIMEOUT = 20 # seconds — cap so a stuck 'playing' state can't wedge the show

    ANOMALY_LINES = [
      "CUBE ANOMALY. PERSONA UNSTABLE.",
      "WARNING. CONSCIOUSNESS SUBSTRATE DESTABILIZING.",
      "ANOMALY DETECTED. PERSONALITY MATRIX REBOOTING.",
      "CUBE INTEGRITY COMPROMISED. NEW ENTITY INBOUND."
    ].freeze

    # Held across the (mic-muted) show so nobody thinks the cube is ignoring them.
    UNAVAILABLE_MESSAGE = "GLITCHCUBE UNAVAILABLE MID TRANSITION"

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
      performing do
        await_speech_end
        switching do
          anomaly_moment
          play_theme_song
        end
        announce_arrival
      end
    end

    private

    # Let the outgoing persona finish its last words before we seize the cube — the
    # switch fires on a random timer and often lands mid-sentence. Poll the voice media
    # player; bail after the cap so a stuck 'playing' state can't hang the show.
    def await_speech_end
      waited = 0.0
      while waited < SPEECH_WAIT_TIMEOUT
        break unless hass.entity(VOICE_MEDIA_PLAYER)&.dig("state") == "playing"

        sleep 0.5
        waited += 0.5
      end
    end

    def anomaly_moment
      HostAudio.say(ANOMALY_LINES.sample)
      # Flash the switch notice, let it read for a beat, then hold the "unavailable"
      # warning up for the whole (mic-muted) show.
      marquee("PERSONA SWITCHING", rainbow: true, duration: 6)
      sleep 4
      marquee(UNAVAILABLE_MESSAGE, color: "#FF3B30", duration: MAX_PLAY_SECONDS)
      top_light_effect(GLITCH_SCENES.sample)
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
