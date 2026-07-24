# app/services/tools/lights/set_light.rb
#
# The generic cube-light tool. Wraps script.set_cube_lights, which owns the
# both/head/body → real-WLED-entity routing (light.glitch_head_wled /
# light.cube_body_wled). We never address a fixture here, so a future light with
# different color args is absorbed script-side or via a new led_strip value.
class Tools::Lights::SetLight < Tools::BaseTool
  def self.definition
    @definition ||= begin
      tool = OpenRouter::Tool.define do
        name "set_cube_lights"
        description <<~DESC.squish
          Set the cube's addressable RGB LEDs (a HEAD strip and a BODY strip on one
          sound-reactive WLED controller). Use for any look: a solid color, a mood, or an
          animated/audio-reactive effect. Pick led_strip "both" (default), "head", or
          "body" — call twice to make head and body differ. color and brightness are
          optional and left unchanged when omitted. effect defaults to Solid (a plain
          color); pass another WLED effect name to animate. Many effects are sound-reactive
          and pulse to live audio (great with music): Freqwave, Freqmatrix, Waterfall,
          Matripix, DJ Light, Blurz, Pixelwave. Calm: Breathe, Aurora, Pacifica, Lake,
          Colorwaves. Warm/fire: Fire 2012, Candle, Sunrise. Eerie/glitchy: Halloween Eyes,
          ICU, TV Simulator, Lightning.
        DESC

        parameters do
          string :led_strip,
                 description: "Which part to light: both (default, same look on head+body), head, or body.",
                 enum: %w[both head body]
          string :color,
                 description: "RGB color as 'R,G,B' with each 0-255, e.g. '255,0,255' for magenta. Omit to leave unchanged."
          number :brightness, minimum: 1, maximum: 100,
                 description: "Overall brightness 1-100%. Omit to leave unchanged."
          string :effect,
                 description: "WLED effect name. Defaults to Solid (plain color). Any other value animates; many are sound-reactive."
        end
      end

      def tool.validation_blocks
        @validation_blocks ||= [
          proc do |params, errors|
            params = params.transform_keys(&:to_s)

            if params["color"].present? && Tools::BaseTool.parse_rgb(params["color"]).nil?
              errors << "Invalid color '#{params["color"]}'. Use 'R,G,B' with each value 0-255, e.g. '255,0,255'."
            end

            if params["brightness"].present? && !(1..100).cover?(params["brightness"].to_i)
              errors << "brightness must be between 1 and 100. Got: #{params["brightness"]}."
            end

            nil # mutate `errors`; don't return an array (ValidatedToolCall would re-append it)
          end
        ]
      end

      tool
    end
  end

  def call(led_strip: nil, color: nil, brightness: nil, effect: nil)
    vars = {}
    vars[:led_strip] = led_strip if led_strip.present?

    if color.present?
      rgb = Tools::BaseTool.parse_rgb(color)
      return error_response("Invalid color '#{color}'. Use 'R,G,B' with each value 0-255, e.g. '255,0,255'.") if rgb.nil?

      vars[:color] = rgb
    end

    vars[:brightness] = brightness.to_i if brightness.present?
    vars[:effect] = effect if effect.present?

    return error_response("Nothing to change — pass at least one of led_strip, color, brightness, effect.") if vars.empty?

    service_call = run_script("set_cube_lights", **vars)
    success_response("Set cube lights (#{vars.keys.join(', ')})", service_calls: [ service_call ])
  end
end
