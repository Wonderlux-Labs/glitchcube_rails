# app/services/tools/base_tool.rb
class Tools::BaseTool
  # Cube light entities (single source of truth)
  CUBE_LIGHT_ENTITIES = %w[
    light.cube_voice_ring
    light.cube_inner
    light.cube_top
    light.awtrix_b85e20_matrix
  ].freeze
  class << self
    # Define the OpenRouter tool definition for this tool
    def definition
      raise NotImplementedError, "Subclasses must implement .definition"
    end
    
    # Human-readable description for persona prompt generation
    def description
      raise NotImplementedError, "Subclasses must implement .description"
    end
    
    # Schema description for prompt generation (simplified for LLM understanding)
    def prompt_schema
      raise NotImplementedError, "Subclasses must implement .prompt_schema"
    end
    
    # Tool execution type for internal orchestration
    def tool_type
      :sync # Default to sync, override for :async or :agent
    end
    
    # Execute the tool with given arguments
    def call(**args)
      new.call(**args)
    end
  end
  
  # Instance method to execute the tool
  def call(**args)
    raise NotImplementedError, "Subclasses must implement #call"
  end
  
  protected
  
  # Validate entity exists and is accessible
  def validate_entity(entity_id, domain: nil)
    entities = HomeAssistantService.entities
    entity = entities.find { |e| e['entity_id'] == entity_id }
    
    if entity.nil?
      available_entities = entities
        .map { |e| e['entity_id'] }
        .select { |id| domain.nil? || id.start_with?("#{domain}.") }
        .sort
        
      return {
        error: "Entity '#{entity_id}' not found",
        available_entities: available_entities.first(10),
        total_entities: available_entities.length
      }
    end
    
    if domain && !entity_id.start_with?("#{domain}.")
      return {
        error: "Entity '#{entity_id}' is not a #{domain} entity",
        actual_domain: entity_id.split('.').first
      }
    end
    
    entity
  end
  
  # Get cube-specific light entities
  def cube_light_entities
    CUBE_LIGHT_ENTITIES
  end
  
  # Get cached effect lists for cube lights (avoids repeated API calls)
  def cube_light_effects
    @cube_light_effects ||= begin
      effects_map = {}
      CUBE_LIGHT_ENTITIES.each do |entity_id|
        begin
          entity_data = HomeAssistantService.entity(entity_id)
          effect_list = entity_data&.dig('attributes', 'effect_list') || []
          effects_map[entity_id] = effect_list.reject(&:empty?).sort
        rescue StandardError => e
          Rails.logger.warn "Could not get effects for #{entity_id}: #{e.message}"
          effects_map[entity_id] = []
        end
      end
      effects_map
    end
  end
  
  # Format successful response
  def success_response(message, data = {})
    {
      success: true,
      message: message,
      **data
    }
  end
  
  # Format error response
  def error_response(message, details = {})
    {
      success: false,
      error: message,
      **details
    }
  end
  
  # Convert RGB array to Home Assistant format
  def format_rgb_color(rgb_color)
    return nil unless rgb_color.is_a?(Array) && rgb_color.length == 3
    return nil unless rgb_color.all? { |c| c.is_a?(Integer) && c >= 0 && c <= 255 }
    
    rgb_color
  end
  
  # Convert brightness percentage to HA brightness (0-255)
  def format_brightness(brightness_percent)
    return nil unless brightness_percent.is_a?(Numeric)
    return nil unless brightness_percent >= 0 && brightness_percent <= 100
    
    (brightness_percent * 2.55).round
  end
end