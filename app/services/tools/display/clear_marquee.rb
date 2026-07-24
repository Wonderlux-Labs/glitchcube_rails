# app/services/tools/display/clear_marquee.rb
#
# Dismiss the current marquee message, returning the sign to its normal display.
# Wraps script.awtrix_marquee_clear.
class Tools::Display::ClearMarquee < Tools::BaseTool
  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "clear_marquee"
      description "Clear/dismiss the current message on the cube's LED marquee sign, " \
                  "returning it to its normal display. No arguments."
    end
  end

  def call(**_ignored)
    service_call = run_script("awtrix_marquee_clear")
    success_response("Marquee cleared", service_calls: [ service_call ])
  end
end
