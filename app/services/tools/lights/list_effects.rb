# app/services/tools/lights/list_effects.rb
class Tools::Lights::ListEffects < Tools::BaseTool
  def self.description
    "List available effects for cube lights"
  end

  def self.narrative_desc
    "check lights - see available effects"
  end

  def self.prompt_schema
    "list_light_effects(entity_id: 'light.cube_inner') - List available effects for a cube light"
  end

  def self.tool_type
    :async # Need immediate data for response
  end

  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "list_light_effects"
      description "List available effects for cube lights"

      parameters do
        string :entity_id, required: true,
               description: "Light entity to check for available effects",
               enum: -> { Tools::Lights::ListEffects.available_entities }
      end
    end
  end

  def self.available_entities
    CUBE_LIGHT_ENTITIES
  end

  def call(entity_id:)
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

    # Get entity state and effects
    begin
      entity_data = HomeAssistantService.entity(entity_id)

      if entity_data.nil?
        return error_response("Could not retrieve data for #{entity_id}")
      end

      attributes = entity_data["attributes"] || {}
      effect_list = attributes["effect_list"] || []
      current_effect = attributes["effect"]

      if effect_list.empty?
        return success_response(
          "#{entity_id} does not support effects",
          entity_id: entity_id,
          supports_effects: false,
          available_effects: []
        )
      end

      success_response(
        "#{entity_id} supports #{effect_list.length} effects" +
        (current_effect ? " (current: #{current_effect})" : ""),
        {
          entity_id: entity_id,
          supports_effects: true,
          available_effects: effect_list,
          current_effect: current_effect,
          effect_count: effect_list.length
        }
      )
    rescue HomeAssistantService::Error => e
      error_response("Failed to get effects list: #{e.message}")
    end
  end
end
