# app/services/tools/lights/set_state.rb
class Tools::Lights::SetState < Tools::BaseTool
  def self.description
    "Unified control for cube lights: turn on/off, set brightness, color, effects, and transitions"
  end

  def self.narrative_desc
    "control lights - unified light control"
  end

  def self.prompt_schema
    "set_light_state(entity_id: 'light.cube_inner', state: 'on', brightness: 80, rgb_color: [255, 0, 0], effect: 'rainbow') - Set any combination of light properties"
  end

  def self.tool_type
    :async # Physical world changes happen after response
  end

  def self.definition
    @definition ||= begin
      tool = OpenRouter::Tool.define do
        name "set_light_state"
        description "Unified control for cube lights: turn on/off, set brightness, color, effects, and transitions"

        parameters do
          string :entity_id, required: true,
                 description: "Light entity to control",
                 enum: -> { Tools::Lights::SetState.available_entities }

          string :state, required: true,
                 description: "Turn light on or off pass on even if on to change state",
                 enum: %w[on off]

          number :brightness, minimum: 0, maximum: 100,
                 description: "Brightness percentage (0-100)"

          array :rgb_color,
                description: "RGB color as [R, G, B] values (0-255). Example: [255, 0, 0] for red" do
            integer minimum: 0, maximum: 255
          end

          string :effect,
                 description: "Light effect name. Use get_light_state to see available effects for each light"

          number :transition, minimum: 0, maximum: 60,
                 description: "Transition time in seconds for smooth changes"
        end
      end

      # Add validation_blocks method to the tool object
      def tool.validation_blocks
        @validation_blocks ||= [
          proc do |params, errors|
            # Convert symbol keys to string keys for consistency
            params = params.transform_keys(&:to_s)

            # 1. Entity validation with suggestions
            if params["entity_id"] && !Tools::BaseTool::CUBE_LIGHT_ENTITIES.include?(params["entity_id"])
              available = Tools::BaseTool::CUBE_LIGHT_ENTITIES.join(", ")
              errors << "Invalid light entity '#{params["entity_id"]}'. Available cube lights: #{available}"
            end

            # 2. RGB color validation with examples
            if params["rgb_color"]
              if !params["rgb_color"].is_a?(Array) || params["rgb_color"].length != 3
                errors << "rgb_color must be an array of 3 integers, e.g., [255, 0, 0] for red, [0, 255, 0] for green"
              elsif params["rgb_color"].any? { |c| !c.is_a?(Integer) || c < 0 || c > 255 }
                invalid = params["rgb_color"].select { |c| !c.is_a?(Integer) || c < 0 || c > 255 }
                errors << "RGB values must be integers 0-255. Invalid values: #{invalid}"
              end
            end

            # 3. Logical validation
            if params["state"] == "off" && (params["brightness"] || params["rgb_color"] || params["effect"])
              errors << "Cannot set brightness, color, or effects when turning light off. Use state: 'on' instead."
            end

            # 4. Smart suggestions
            if params["rgb_color"] == [ 0, 0, 0 ]
              errors << "RGB [0, 0, 0] is black (no light). Did you mean to set state: 'off' instead?"
            end

            # 5. Brightness warnings
            if params["brightness"] && params["brightness"] < 5 && params["state"] == "on"
              errors << "Brightness #{params["brightness"]}% is very dim. Consider 20% or higher for visibility."
            end
          end
        ]
      end

      tool
    end
  end

  def self.available_entities
    CUBE_LIGHT_ENTITIES
  end

  # Helper method for validation - get live effects for an entity
  def self.get_live_effects_for(entity_id)
    @effects_cache ||= {}
    @effects_cache[entity_id] ||= begin
      entity_data = HomeAssistantService.entity(entity_id)
      entity_data&.dig("attributes", "effect_list") || []
    rescue
      []
    end
  end

  # Helper method for validation - check if light is responsive
  def self.light_is_responsive?(entity_id)
    entity_data = HomeAssistantService.entity(entity_id)
    entity_data.present? && entity_data["state"] != "unavailable"
  rescue
    false
  end

  def call(entity_id:, state: nil, brightness: nil, rgb_color: nil, effect: nil, transition: nil)
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
    if [ state, brightness, rgb_color, effect, transition ].all?(&:nil?)
      return error_response(
        "Must specify at least one parameter to change",
        examples: {
          turn_on: { entity_id: entity_id, state: "on" },
          set_brightness: { entity_id: entity_id, brightness: 75 },
          set_color: { entity_id: entity_id, rgb_color: [ 255, 0, 0 ] },
          set_effect: { entity_id: entity_id, effect: "rainbow" }
        }
      )
    end

    # Handle off state specially
    if state == "off"
      begin
        result = HomeAssistantService.call_service("light", "turn_off", { entity_id: entity_id })
        return success_response(
          "Turned off #{entity_id}",
          { entity_id: entity_id, state: "off", service_result: result }
        )
      rescue HomeAssistantService::Error => e
        return error_response("Failed to turn off light: #{e.message}")
      end
    end

    # Prepare service data for turn_on
    service_data = { entity_id: entity_id }
    changes = []

    # Add brightness if provided
    if brightness
      formatted_brightness = format_brightness(brightness)
      if formatted_brightness.nil?
        return error_response(
          "Invalid brightness. Must be number between 0-100",
          example: 75
        )
      end
      service_data[:brightness] = formatted_brightness
      changes << "brightness: #{brightness}%"
    end

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
      changes << "color: RGB(#{rgb_color.join(', ')})"
    end

    # Add effect if provided
    if effect
      service_data[:effect] = effect
      changes << "effect: #{effect}"
    end

    # Add transition if provided
    if transition
      service_data[:transition] = transition
      changes << "transition: #{transition}s"
    end

    # Call Home Assistant service
    begin
      result = HomeAssistantService.call_service("light", "turn_on", service_data)

      response_data = {
        entity_id: entity_id,
        service_result: result,
        changes_applied: changes
      }

      # Include the parameters that were set
      response_data[:state] = state if state
      response_data[:brightness] = brightness if brightness
      response_data[:rgb_color] = rgb_color if rgb_color
      response_data[:effect] = effect if effect
      response_data[:transition] = transition if transition

      success_response(
        "Set #{entity_id}" + (changes.any? ? " - #{changes.join(', ')}" : ""),
        response_data
      )
    rescue HomeAssistantService::Error => e
      error_response("Failed to set light state: #{e.message}")
    end
  end
end
