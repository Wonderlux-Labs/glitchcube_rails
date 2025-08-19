# app/services/tools/communication/announcement.rb
class Tools::Communication::Announcement < Tools::BaseTool
  def self.description
    "Make spoken announcements with persona voice and optional display text"
  end

  def self.narrative_desc
    "make announcements - speak to humans and display messages on your screen - you have a loudspeaker after all! can send separate spoken and text or both the same"
  end

  def self.prompt_schema
    "make_announcement(message: 'Welcome to the Cube', display_text: 'Welcome!') - Make spoken announcement with optional display"
  end

  def self.tool_type
    :async # Announcements happen after response
  end

  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "make_announcement"
      description "Make spoken announcements using music_assistant with persona voice and optional Awtrix display"

      parameters do
        string :message, required: true,
               description: "Message to speak aloud"

        string :display_text,
               description: "Optional text to display on Awtrix matrix (if different from spoken message)"

        number :volume, minimum: 0, maximum: 100,
               description: "Volume level for announcement (0-100)"

        string :voice,
               description: "Voice to use (will default to current persona voice)"
      end
    end
  end

  def call(message:, display_text: nil, volume: nil, voice: nil)
    results = {}

    # Make spoken announcement using music_assistant
    begin
      announce_data = {
        message: message
      }

      # Add optional parameters
      announce_data[:volume_level] = volume / 100.0 if volume.present?
      announce_data[:voice] = voice if voice.present?

      # Call music_assistant announce service
      speech_result = HomeAssistantService.call_service(
        "music_assistant",
        "announce",
        announce_data
      )

      results[:speech] = { success: true, message: "Announced: \"#{message}\"" }

    rescue HomeAssistantService::Error => e
      results[:speech] = { success: false, error: e.message }
    end

    # Display text on Awtrix if requested
    if display_text.present?
      begin
        display_data = {
          variables: {
            text: display_text,
            duration: 8 # Display for 8 seconds
          }
        }

        display_result = HomeAssistantService.call_service(
          "script",
          "notification",
          display_data
        )

        results[:display] = { success: true, message: "Displayed: \"#{display_text}\"" }

      rescue HomeAssistantService::Error => e
        results[:display] = { success: false, error: e.message }
      end
    end

    # Build response
    if results[:speech][:success]
      response_parts = [ "Made announcement" ]
      response_parts << "and displayed text" if results[:display]&.dig(:success)

      success_response(
        response_parts.join(" "),
        message: message,
        display_text: display_text,
        volume: volume,
        voice: voice,
        results: results
      )
    else
      error_response(
        "Failed to make announcement: #{results[:speech][:error]}",
        results: results
      )
    end
  end
end
