# frozen_string_literal: true

module Shows
  # The glitch-light vocabulary shared by the glitch shows. Drives the two WLED
  # show strips (head + body) DIRECTLY — light.turn_on/off, no HASS script hop —
  # because glitching wants tight, responsive control. Mixed into a Show (needs
  # #hass and Base::WLED_LIGHTS from Shows::Base).
  #
  # The core trick: play the audio in a background thread and keep firing glitch
  # beats `while` it's alive. When ffplay exits (clip ends, or its max_seconds
  # cap fires) the lights stop — so the glitching is frame-locked to the sound
  # with no need to know the clip's duration up front.
  module GlitchLights
    # A curated slice of the WLED catalog that reads as broken/unstable.
    GLITCH_EFFECTS = [
      "Strobe", "Strobe Mega", "Lightning", "Chase Flash", "Distortion Waves",
      "Frizzles", "Black Hole", "Matrix", "Noise 1", "TV Simulator",
      "Ghost Rider", "Blink Rainbow"
    ].freeze

    # Vivid, saturated pops — the colors a glitching screen throws.
    GLITCH_COLORS = [
      [ 255, 0, 255 ], [ 0, 255, 255 ], [ 0, 255, 0 ], [ 255, 0, 0 ],
      [ 0, 120, 255 ], [ 255, 255, 255 ], [ 255, 60, 0 ]
    ].freeze

    BEATS = %i[cutout color effect split].freeze

    BLACKOUT_RANGE = (0.08..0.22)  # a cutout's dark gap
    BEAT_PAUSE_RANGE = (0.12..0.45) # dwell between beats
    FALLBACK_BEATS = 12 # a clipless burst (empty efx dir) so the show isn't dead air

    # Glitch shows only burble in the background — a low random level so they never
    # blare like a cued jukebox song. HASS quiet_mode can still cap this lower.
    GLITCH_VOLUME_RANGE = (25..50)

    private

    # A random low playback volume (percent) for a glitch run. Pick once per show so
    # the level holds steady across a long show's segments instead of jumping.
    def glitch_volume
      rand(GLITCH_VOLUME_RANGE)
    end

    # Glitch the strips while a clip plays — capped (long-show segments) or to its
    # natural end (short show). A nil clip (empty efx dir) still throws the
    # fallback burst so the show isn't dead air.
    def play_glitching(clip, max_seconds: nil, volume: nil)
      if clip
        glitch_lights { HostAudio.play(clip, max_seconds: max_seconds, volume: volume) }
      else
        glitch_lights
      end
    end

    # Glitch the strips for as long as the given audio block runs — beats keep
    # firing until the ffplay thread exits, so the lights are frame-locked to the
    # sound without knowing its length. With no block (empty clip dir) it throws a
    # fixed burst instead. Always fires at least one beat.
    def glitch_lights(&audio)
      return FALLBACK_BEATS.times { glitch_beat } unless audio

      thread = Thread.new(&audio)
      thread.report_on_exception = false # we surface any ffplay failure at #join, not on stderr
      loop do
        glitch_beat
        break unless thread.alive?
      end
    ensure
      thread&.join
    end

    def glitch_beat
      send("beat_#{BEATS.sample}")
      pause(rand(BEAT_PAUSE_RANGE))
    end

    def beat_cutout
      wled(Base::WLED_LIGHTS, service: "turn_off")
      pause(rand(BLACKOUT_RANGE))
      wled(Base::WLED_LIGHTS, effect: "Solid", rgb_color: GLITCH_COLORS.sample)
    end

    def beat_color
      wled(Base::WLED_LIGHTS, effect: "Solid", rgb_color: GLITCH_COLORS.sample, brightness_pct: 100)
    end

    def beat_effect
      wled(Base::WLED_LIGHTS, effect: GLITCH_EFFECTS.sample)
    end

    # Desync: head and body take different looks in the same beat.
    def beat_split
      head, body = Base::WLED_LIGHTS
      wled([ head ], effect: GLITCH_EFFECTS.sample)
      wled([ body ], effect: "Solid", rgb_color: GLITCH_COLORS.sample)
    end

    def wled(entity_ids, service: "turn_on", **data)
      hass.call_service("light", service, entity_id: entity_ids, **data)
    end

    # Seam so specs can neutralize the real sleeps without touching timing logic.
    def pause(seconds)
      sleep(seconds)
    end
  end
end
