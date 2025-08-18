# app/services/tools/lights/turn_on.rb
class Tools::Lights::TurnOn < Tools::BaseTool
  def self.description
    "Turn on cube lights with optional transition time"
  end
  
  def self.prompt_schema
    "turn_on_light(entity_id: 'light.cube_voice_ring', transition: 2.0) - Turn on a cube light"
  end
  
  def self.tool_type
    :async # Light control happens after response
  end
  
  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "turn_on_light"
      description "Turn on cube lights (cube_light, cube_voice_ring, or specific cube segments)"
      
      parameters do
        string :entity_id, required: true,
               description: "Light entity to turn on",
               enum: -> { Tools::Lights::TurnOn.available_entities }
        
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
      result = HomeAssistantService.call_service('light', 'turn_on', service_data)
      
      success_response(
        "Turned on #{entity_id}",
        entity_id: entity_id,
        transition: transition,
        service_result: result
      )
    rescue HomeAssistantService::Error => e
      error_response("Failed to turn on light: #{e.message}")
    end
  end
end