# app/services/tools/lights/turn_off.rb
class Tools::Lights::TurnOff < Tools::BaseTool
  def self.description
    "Turn off cube lights with optional transition time"
  end
  
  def self.narrative_desc
    "control lights - turn lights off"
  end
  
  def self.prompt_schema
    "turn_off_light(entity_id: 'light.cube_voice_ring', transition: 1.0) - Turn off a cube light"
  end
  
  def self.tool_type
    :async # Light control happens after response
  end
  
  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "turn_off_light"
      description "Turn off cube lights (cube_light, cube_voice_ring, or specific cube segments)"
      
      parameters do
        string :entity_id, required: true,
               description: "Light entity to turn off",
               enum: -> { Tools::Lights::TurnOff.available_entities }
        
        number :transition, minimum: 0, maximum: 300,
               description: "Transition time in seconds (optional)"
      end
    end
  end
  
  def self.available_entities
    CUBE_LIGHT_ENTITIES
  end
  
  def call(entity_id:, transition: nil)
    # Validate entity
    entity = validate_entity(entity_id, domain: 'light')
    return entity if entity.is_a?(Hash) && entity[:error]
    
    # Ensure it's a cube light
    unless cube_light_entities.include?(entity_id)
      return error_response(
        "Entity '#{entity_id}' is not a cube light",
        available_lights: cube_light_entities
      )
    end
    
    # Prepare service data
    service_data = { entity_id: entity_id }
    service_data[:transition] = transition if transition
    
    # Call Home Assistant service
    begin
      result = HomeAssistantService.call_service('light', 'turn_off', service_data)
      
      success_response(
        "Turned off #{entity_id}",
        entity_id: entity_id,
        transition: transition,
        service_result: result
      )
    rescue HomeAssistantService::Error => e
      error_response("Failed to turn off light: #{e.message}")
    end
  end
end