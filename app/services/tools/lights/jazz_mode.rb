# app/services/tools/lights/jazz_mode.rb
#
# Script-preset: a calm, warm, ambient look. Picks a RANDOM slow effect, a warm color,
# and moderate brightness on both strips via script.set_cube_lights. The mellow
# counterpart to dance mode.
class Tools::Lights::JazzMode < Tools::BaseTool
  # Slow / ambient WLED effects (see cube_lights.yaml "CALM/AMBIENT" picks).
  EFFECTS = [
    "Breathe", "Aurora", "Pacifica", "Lake", "Colorwaves", "Palette",
    "Colorloop", "Twinkleup", "Slow Transition"
  ].freeze

  # Warm, low-key RGB colors that read as candlelit/lounge.
  COLORS = [
    [ 255, 120, 40 ], [ 200, 60, 90 ], [ 180, 80, 160 ], [ 230, 150, 60 ], [ 120, 60, 180 ]
  ].freeze

  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "set_lights_to_jazz_mode"
      description "Set a calm, warm, ambient lounge look — a random slow effect in a warm " \
                  "color at moderate brightness on both strips. The mellow counterpart to " \
                  "dance mode. No arguments."
    end
  end

  def call(**_ignored)
    service_call = run_script(
      "set_cube_lights",
      led_strip: "both", effect: EFFECTS.sample, color: COLORS.sample, brightness: 45
    )
    success_response("Cube is in jazz mode", service_calls: [ service_call ])
  end
end
