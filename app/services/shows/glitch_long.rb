# frozen_string_literal: true

module Shows
  # The extended glitch-out: a long static bed, a short stab, then another long
  # bed — 45-85s of the cube coming apart, WLED strips glitching the whole way.
  # Saves the lights first and puts them back after; mutes the mic throughout.
  class GlitchLong < Base
    include GlitchLights

    LONG_SEGMENT_RANGE = (20..40)
    SHORT_SEGMENT_SECONDS = 5

    def call
      performing do
        switching do
          preserving_lights do
            volume = glitch_volume
            segments.each do |kind, seconds|
              play_glitching(HostAudio.random_glitch_efx(kind), max_seconds: seconds, volume: volume)
            end
          end
        end
      end
    end

    private

    # long bed -> short stab -> long bed. The two long durations are randomized
    # per run; a private method so specs can pin them.
    def segments
      [
        [ :long, rand(LONG_SEGMENT_RANGE) ],
        [ :short, SHORT_SEGMENT_SECONDS ],
        [ :long, rand(LONG_SEGMENT_RANGE) ]
      ]
    end
  end
end
