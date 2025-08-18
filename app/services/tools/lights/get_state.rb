# app/services/tools/lights/get_state.rb
class Tools::Lights::GetState < Tools::BaseTool
  def self.description
    "Get current state, brightness, color, and attributes of cube lights"
  end
  
  def self.prompt_schema
    "get_light_state(entity_id: 'light.cube_voice_ring') - Get current state of a cube light"
  end
  
  def self.tool_type
    :sync # Need immediate data for response
  end
  
  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "get_light_state"
      description "Get current state, brightness, color, and attributes of cube lights"
      
      parameters do
        string :entity_id, required: true,
               description: "Light entity to check",
               enum: -> { Tools::Lights::GetState.available_entities }
      end
    end
  end
  
  def self.available_entities
    CUBE_LIGHT_ENTITIES
  end
  
  def call(entity_id:)
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
    
    # Get entity state
    begin
      entity_data = HomeAssistantService.entity(entity_id)
      
      if entity_data.nil?
        return error_response("Could not retrieve state for #{entity_id}")
      end
      
      # Extract useful information
      state = entity_data['state']
      attributes = entity_data['attributes'] || {}
      
      response_data = {
        entity_id: entity_id,
        state: state,
        is_on: state == 'on'
      }
      
      # Add brightness if available
      if attributes['brightness']
        brightness_percent = (attributes['brightness'] / 2.55).round
        response_data[:brightness] = {
          raw_value: attributes['brightness'],
          percentage: brightness_percent
        }
      end
      
      # Add color information if available
      if attributes['rgb_color']
        response_data[:color] = {
          rgb: attributes['rgb_color'],
          rgb_string: "RGB(#{attributes['rgb_color'].join(', ')})"
        }
      end
      
      if attributes['hs_color']
        response_data[:color] ||= {}
        response_data[:color][:hue_saturation] = attributes['hs_color']
      end
      
      # Add effect if available
      if attributes['effect']
        response_data[:effect] = attributes['effect']
      end
      
      # Add supported features
      if attributes['supported_color_modes']
        response_data[:supported_color_modes] = attributes['supported_color_modes']
      end
      
      if attributes['supported_features']
        response_data[:supported_features] = attributes['supported_features']
      end
      
      success_response(
        "Current state of #{entity_id}: #{state}" + 
        (response_data[:brightness] ? " (#{response_data[:brightness][:percentage]}% brightness)" : "") +
        (response_data[:color] ? " #{response_data[:color][:rgb_string]}" : ""),
        response_data
      )
    rescue HomeAssistantService::Error => e
      error_response("Failed to get light state: #{e.message}")
    end
  end
end