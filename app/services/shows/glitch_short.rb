# frozen_string_literal: true

module Shows
  # A quick glitch fit: one random short glitch-radio stab out the host speaker
  # while the WLED strips spasm, for exactly as long as the clip runs. Saves the
  # lights first and puts them back after; mutes the mic for the duration.
  class GlitchShort < Base
    include GlitchLights

    def call
      performing do
        switching do
          preserving_lights do
            play_glitching(HostAudio.random_glitch_efx(:short), volume: glitch_volume)
          end
        end
      end
    end
  end
end
