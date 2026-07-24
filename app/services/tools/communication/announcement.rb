# app/services/tools/communication/announcement.rb
#
# An official, robotic, non-persona announcement over the jukebox speaker. Wraps
# script.system_announcement (plays a chime, ducks music, speaks, resumes). message
# required; volume optional (script defaults to 75). For genuine system notices or
# rare, sparing in-world trolling — not for regular persona speech.
class Tools::Communication::Announcement < Tools::BaseTool
  def self.definition
    @definition ||= begin
      tool = OpenRouter::Tool.define do
        name "make_announcement"
        description "Make an official system announcement in a robotic, non-persona voice over " \
                    "the jukebox speaker — plays a chime, ducks any music, speaks, then resumes. " \
                    "For genuine system notices or rare in-world trolling, not regular persona " \
                    "speech. Keep it to a few sentences and use sparingly."
        parameters do
          string :message, required: true, description: "The announcement text. Keep it short — a few sentences max."
          number :volume, minimum: 0, maximum: 100, description: "Volume 0-100%. Defaults to 75."
        end
      end

      def tool.validation_blocks
        @validation_blocks ||= [
          proc do |params, errors|
            params = params.transform_keys(&:to_s)

            errors << "message is required." if params["message"].blank?

            if params["volume"].present? && !(0..100).cover?(params["volume"].to_i)
              errors << "volume must be between 0 and 100. Got: #{params["volume"]}."
            end

            nil # mutate `errors`; don't return an array (ValidatedToolCall would re-append it)
          end
        ]
      end

      tool
    end
  end

  def call(message:, volume: nil)
    return error_response("message is required.") if message.blank?

    vars = { message: message }
    vars[:volume] = volume.to_i if volume.present?

    service_call = run_script("system_announcement", **vars)
    success_response("Announcing: #{message}", service_calls: [ service_call ])
  end
end
