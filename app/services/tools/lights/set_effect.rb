# app/services/tools/lights/set_effect.rb
class Tools::Lights::SetEffect < Tools::BaseTool
  def self.description
    "Set lighting effects on cube lights that support them. Call list_light_effects first to see available effects for each entity."
  end

  def self.narrative_desc
    "control lights - apply special effects"
  end

  def self.prompt_schema
    "set_light_effect(entity_id: 'light.cube_inner', effect: 'Rainbow') - Set a lighting effect. Use list_light_effects to see all available effects."
  end

  def self.tool_type
    :async # Light control happens after response
  end

  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "set_light_effect"
      description "Set lighting effects on cube lights that support them"

      parameters do
        string :entity_id, required: true,
               description: "Light entity to control",
               enum: -> { Tools::Lights::SetEffect.available_entities }

        string :effect, required: true,
               description: "Effect name to apply (use list_light_effects to see available options)"

        number :transition, minimum: 0, maximum: 300,
               description: "Transition time in seconds (optional)"
      end
    end
  end

  def self.available_entities
    CUBE_LIGHT_ENTITIES
  end

  def call(entity_id:, effect:, transition: nil)
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

    # Fast validation using cached effect lists (no API call needed)
    cached_effects = cube_light_effects
    available_effects = cached_effects[entity_id] || []

    if available_effects.empty?
      return error_response(
        "#{entity_id} does not support effects",
        entity_id: entity_id,
        supports_effects: false
      )
    end

    unless available_effects.include?(effect)
      return error_response(
        "Effect '#{effect}' is not available for #{entity_id}",
        entity_id: entity_id,
        requested_effect: effect,
        available_effects: available_effects,
        effects_count: available_effects.length
      )
    end

    # Now make the actual API call to set the effect
    begin

      # Prepare service data
      service_data = {
        entity_id: entity_id,
        effect: effect
      }
      service_data[:transition] = transition if transition

      # Call Home Assistant service
      result = HomeAssistantService.call_service("light", "turn_on", service_data)

      response_data = {
        entity_id: entity_id,
        effect: effect,
        service_result: result
      }
      response_data[:transition] = transition if transition

      success_response(
        "Set #{entity_id} effect to '#{effect}'" +
        (transition ? " with #{transition}s transition" : ""),
        response_data
      )
    rescue HomeAssistantService::Error => e
      error_response("Failed to set light effect: #{e.message}")
    end
  end
end
