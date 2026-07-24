# app/services/tools/display/marquee.rb
#
# Flash a message across the cube's AWTRIX LED sign. Wraps script.awtrix_marquee_message
# (only `message` is required); the script handles the MQTT plumbing and brightness restore.
class Tools::Display::Marquee < Tools::BaseTool
  def self.definition
    @definition ||= OpenRouter::Tool.define do
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
