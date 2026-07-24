# app/services/tools/lights/dance_mode.rb
#
# Script-preset: throw the cube into a sound-reactive dance look. Picks a RANDOM
# sound-reactive WLED effect and cranks brightness on both strips via
# script.set_cube_lights. Great while music is playing on the jukebox.
class Tools::Lights::DanceMode < Tools::BaseTool
  # Sound-reactive WLED effects that pulse to the live mic (see cube_lights.yaml).
  EFFECTS = [
    "Freqwave", "Freqmatrix", "Waterfall", "Matripix", "Gravcenter", "Gravcentric",
    "Gravfreq", "DJ Light", "Blurz", "Puddlepeak", "Pixelwave", "Rocktaves",
    "Midnoise", "Noisemeter", "PS Sonic Stream", "PS Sonic Boom", "PS GEQ 1D"
  ].freeze

  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "set_lights_to_dance_mode"
      description "Throw the cube into a high-energy sound-reactive dance look — a random " \
                  "audio-reactive WLED effect at full brightness on both strips. Best while " \
                  "music is playing on the jukebox. No arguments."
    end
  end

  def call(**_ignored)
    service_call = run_script("set_cube_lights", led_strip: "both", effect: EFFECTS.sample, brightness: 90)
    success_response("Cube is in dance mode", service_calls: [ service_call ])
  end
end
