# app/services/tools/display/notification.rb
class Tools::Display::Notification < Tools::BaseTool
  def self.description
    "Display text notifications on the Awtrix matrix via MQTT notification script"
  end

  def self.narrative_desc
    "display text - show messages and notifications on the matrix display"
  end

  def self.prompt_schema
    "display_notification(text: 'Hello World', duration: 5) - Display text notification on Awtrix matrix"
  end

  def self.tool_type
    :async # Display control happens after response
  end

  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "display_notification"
      description "Display text notification on the Awtrix matrix display via MQTT script"

      parameters do
        string :text, required: true,
               description: "Text message to display on the matrix"

        number :duration, minimum: 1, maximum: 60,
               description: "How long to display the message in seconds (default: 5)"

        string :color,
               description: "Text color (e.g., 'red', 'green', 'blue', 'white', 'yellow')"

        string :icon,
               description: "Icon to display with the text (optional)"
      end
    end
  end

  def call(text:, duration: 5, color: nil, icon: nil)
    # Build service data for the script call
    service_data = {}

    # Add variables for the script
    variables = {
      text: text,
      duration: duration
    }
    variables[:color] = color if color.present?
    variables[:icon] = icon if icon.present?

    service_data[:variables] = variables

    # Call the Home Assistant script
    begin
      result = HomeAssistantService.call_service("script", "notification", service_data)

      response_message = "Displaying notification: \"#{text}\""
      response_message += " for #{duration} seconds" if duration != 5
      response_message += " in #{color}" if color

      success_response(
        response_message,
        script: "notification",
        text: text,
        duration: duration,
        color: color,
        icon: icon,
        service_result: result
      )
    rescue HomeAssistantService::Error => e
      error_response("Failed to display notification: #{e.message}")
    end
  end
end
