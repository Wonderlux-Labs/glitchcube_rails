# app/services/tools/display/marquee.rb
#
# Flash a message across the cube's AWTRIX LED sign. Wraps script.awtrix_marquee_message
# (only `message` is required); the script handles the MQTT plumbing and brightness restore.
class Tools::Display::Marquee < Tools::BaseTool
  def self.definition
    @definition ||= begin
      tool = OpenRouter::Tool.define do
        name "show_marquee_message"
        description "Flash a short message across the cube's LED marquee sign, then it returns " \
                    "to its normal display. Only message is required. Optionally set a hex color " \
                    "(e.g. '#FF00AA'), turn on rainbow text, set how many seconds it shows " \
                    "(duration), an AWTRIX icon id, or how many times it scrolls (repeat)."
        parameters do
          string :message, required: true, description: "Text to scroll across the marquee (keep under ~255 chars)."
          string :color, description: "Optional text color as a hex string, e.g. '#FF00AA'. Ignored when rainbow is on."
          boolean :rainbow, description: "Rainbow-cycle the text color (overrides color)."
          number :duration, minimum: 1, maximum: 120, description: "Seconds to display before returning to the normal loop."
          string :icon, description: "Optional AWTRIX icon id (a number as a string) shown left of the text, e.g. '87'."
          number :repeat, minimum: 1, maximum: 10, description: "How many times it scrolls before dismissing (default 2)."
        end
      end

      def tool.validation_blocks
        @validation_blocks ||= [
          proc do |params, errors|
            params = params.transform_keys(&:to_s)

            errors << "message is required." if params["message"].blank?

            if params["color"].present? && !Tools::BaseTool.valid_hex_color?(params["color"])
              errors << "Invalid color '#{params["color"]}'. Use a 6-digit hex string, e.g. '#FF00AA'."
            end

            if params["duration"].present? && !(1..120).cover?(params["duration"].to_i)
              errors << "duration must be between 1 and 120 seconds. Got: #{params["duration"]}."
            end

            if params["repeat"].present? && !(1..10).cover?(params["repeat"].to_i)
              errors << "repeat must be between 1 and 10. Got: #{params["repeat"]}."
            end

            nil # mutate `errors`; don't return an array (ValidatedToolCall would re-append it)
          end
        ]
      end

      tool
    end
  end

  def call(message:, color: nil, rainbow: nil, duration: nil, icon: nil, repeat: nil)
    return error_response("message is required.") if message.blank?

    vars = { message: message }
    vars[:color] = color if color.present?
    vars[:rainbow] = rainbow unless rainbow.nil?
    vars[:duration] = duration.to_i if duration.present?
    vars[:icon] = icon.to_s if icon.present?
    vars[:repeat] = repeat.to_i if repeat.present?

    service_call = run_script("awtrix_marquee_message", **vars)
    success_response("Marquee flashing: #{message}", service_calls: [ service_call ])
  end
end
