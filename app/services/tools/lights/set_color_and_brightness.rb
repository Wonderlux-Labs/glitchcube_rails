# app/services/tools/lights/set_color_and_brightness.rb
class Tools::Lights::SetColorAndBrightness < Tools::BaseTool
  def self.description
    "Set color and/or brightness for cube lights. Can control color, brightness, or both together."
  end

  def self.narrative_desc
    "control lights - change colors and brightness"
  end

  def self.prompt_schema
    "set_light_color_and_brightness(entity_id: 'light.cube_voice_ring', rgb_color: [255, 0, 0], brightness_percent: 75) - Set light color to red at 75% brightness"
  end

  def self.tool_type
    :async # Light control happens after response
  end

  def self.definition
    @definition ||= begin
      tool = OpenRouter::Tool.define do
        name "set_light_color_and_brightness"
        description "Set color and/or brightness for cube lights. Can set color only, brightness only, or both."

        parameters do
          string :entity_id, required: true,
                 description: "Light entity to control",
                 enum: -> { Tools::Lights::SetColorAndBrightness.available_entities }

          array :rgb_color,
                description: "RGB color as array of 3 integers (0-255). Example: [255, 0, 0] for red"

          number :brightness_percent, minimum: 0, maximum: 100,
                 description: "Brightness as percentage (0-100). Example: 75 for 75% brightness"

          number :transition, minimum: 0, maximum: 300,
                 description: "Transition time in seconds (optional)"
        end
      end

      # Fix array parameter by adding items specification
      if tool.parameters.dig(:properties, :rgb_color)
        tool.parameters[:properties][:rgb_color][:items] = {
          type: "integer",
          minimum: 0,
          maximum: 255
        }
      end

      tool
    end
  end

  def self.available_entities
    CUBE_LIGHT_ENTITIES
  end

  def call(entity_id:, rgb_color: nil, brightness_percent: nil, transition: nil)
    # Validate entity
    entity = validate_entity(entity_id, domain: "light")
    return entity if entity.is_a?(Hash) && entity[:error]

    # Ensure it's a cube light
    unless cube_light_entities.include?(entity_id)
      return error_response(
        "Entity '#{entity_id}' is not a cube light",
        available_lights: cube_light_entities
      )
    end

    # Must specify at least one parameter
    if rgb_color.nil? && brightness_percent.nil?
      return error_response(
        "Must specify rgb_color, brightness_percent, or both",
        example: {
          rgb_color: [ 255, 0, 0 ],
          brightness_percent: 75
        }
      )
    end

    # Prepare service data
    service_data = { entity_id: entity_id }

    # Add RGB color if provided
    if rgb_color
      formatted_rgb = format_rgb_color(rgb_color)
      if formatted_rgb.nil?
        return error_response(
          "Invalid rgb_color. Must be array of 3 integers (0-255)",
          example: [ 255, 128, 0 ]
        )
      end
      service_data[:rgb_color] = formatted_rgb
    end

    # Add brightness if provided
    if brightness_percent
      formatted_brightness = format_brightness(brightness_percent)
      if formatted_brightness.nil?
        return error_response(
          "Invalid brightness_percent. Must be number between 0-100",
          example: 75
        )
      end
      service_data[:brightness] = formatted_brightness
    end

    # Add transition if provided
    service_data[:transition] = transition if transition

    # Call Home Assistant service
    begin
      result = HomeAssistantService.call_service("light", "turn_on", service_data)

      response_data = {
        entity_id: entity_id,
        service_result: result
      }

      response_data[:rgb_color] = rgb_color if rgb_color
      response_data[:brightness_percent] = brightness_percent if brightness_percent
      response_data[:transition] = transition if transition

      success_response(
        "Set #{entity_id} - " +
        [
          rgb_color ? "color: RGB(#{rgb_color.join(', ')})" : nil,
          brightness_percent ? "brightness: #{brightness_percent}%" : nil
        ].compact.join(", "),
        response_data
      )
    rescue HomeAssistantService::Error => e
      error_response("Failed to set light properties: #{e.message}")
    end
  end
end
