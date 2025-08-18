# app/services/tools/registry.rb
class Tools::Registry
  class << self
    # Get all available tools
    def all_tools
      @all_tools ||= {
        # Light tools
        "turn_on_light" => Tools::Lights::TurnOn,
        "turn_off_light" => Tools::Lights::TurnOff,
        "set_light_color_and_brightness" => Tools::Lights::SetColorAndBrightness,
        "set_light_effect" => Tools::Lights::SetEffect,
        "list_light_effects" => Tools::Lights::ListEffects,
        "get_light_state" => Tools::Lights::GetState,

        # General Home Assistant tools
        "call_hass_service" => Tools::HomeAssistant::CallService
      }
    end

    # Get tools by execution type
    def sync_tools
      all_tools.select { |name, tool_class| tool_class.tool_type == :sync }
    end

    def async_tools
      all_tools.select { |name, tool_class| tool_class.tool_type == :async }
    end

    def agent_tools
      all_tools.select { |name, tool_class| tool_class.tool_type == :agent }
    end

    # Get OpenRouter tool definitions for LLM
    def tool_definitions_for_llm
      all_tools.values.map(&:definition)
    end

    # Get tool by name
    def get_tool(tool_name)
      all_tools[tool_name]
    end

    # Execute a tool
    def execute_tool(tool_name, **args)
      tool_class = get_tool(tool_name)
      return { error: "Tool '#{tool_name}' not found" } unless tool_class

      tool_class.call(**args)
    end

    # Get tool descriptions for prompt generation
    def tool_descriptions
      all_tools.transform_values(&:description)
    end

    # Get tool schemas for prompt generation
    def tool_schemas
      all_tools.transform_values(&:prompt_schema)
    end

    # Generate prompt-friendly tool list
    def prompt_tool_list
      all_tools.map do |name, tool_class|
        "#{tool_class.prompt_schema} [#{tool_class.tool_type}]"
      end.join("\n")
    end

    # Light-specific tools only
    def light_tools
      all_tools.select { |name, _| name.include?("light") }
    end

    # Get available cube light entities (cached)
    def cube_light_entities
      @cube_light_entities ||= begin
        service = HomeAssistantService.instance
        entities = service.entities rescue []

        cube_lights = entities
          .select { |e| e["entity_id"].start_with?("light.cube_") }
          .map { |e| e["entity_id"] }

        # Add ring light if it exists
        ring_light = entities.find { |e| e["entity_id"] == "light.cube_voice_ring" }
        cube_lights << "light.cube_voice_ring" if ring_light

        cube_lights.sort
      end
    end

    # Categorize tool calls by execution type for conversation orchestrator
    def categorize_tool_calls(tool_calls)
      return { sync_tools: [], async_tools: [] } unless tool_calls&.any?

      sync_tools = []
      async_tools = []

      tool_calls.each do |call|
        tool_name = call.respond_to?(:name) ? call.name : call["name"]
        tool_class = get_tool(tool_name)

        next unless tool_class

        case tool_class.tool_type
        when :sync
          sync_tools << call
        when :async
          async_tools << call
        end
      end

      { sync_tools: sync_tools, async_tools: async_tools }
    end

    # Execute sync tools only (for conversation orchestrator)
    def execute_sync_tools(tool_calls)
      return {} if tool_calls.blank?

      results = {}
      tool_calls.each do |tool_call|
        tool_name = tool_call.respond_to?(:name) ? tool_call.name : tool_call["name"]
        arguments = tool_call.respond_to?(:arguments) ? tool_call.arguments : tool_call["arguments"]

        tool_class = get_tool(tool_name)
        next unless tool_class&.tool_type == :sync

        begin
          result = execute_tool(tool_name, **arguments.symbolize_keys)
          results[tool_name] = result
        rescue StandardError => e
          results[tool_name] = { success: false, error: e.message, tool: tool_name }
        end
      end

      results
    end

    # Get tools for specific persona (for conversation orchestrator)
    def tools_for_persona(persona)
      # All personas currently get access to lighting tools
      # This could be made more granular based on persona capabilities
      lighting_tool_classes = [
        Tools::Lights::TurnOn,
        Tools::Lights::TurnOff,
        Tools::Lights::SetColorAndBrightness,
        Tools::Lights::SetEffect,
        Tools::Lights::ListEffects,
        Tools::Lights::GetState
      ]
      
      case persona&.to_s&.downcase
      when "buddy"
        # Buddy gets all lighting tools with enthusiastic descriptions
        lighting_tool_classes
      when "jax"
        # Jax gets all lighting tools for dramatic effect
        lighting_tool_classes
      when "zorp"
        # Zorp gets lighting tools for behavioral experiments
        lighting_tool_classes
      when "lomi"
        # Lomi gets lighting tools for healing environments
        lighting_tool_classes
      else
        # Default persona gets all lighting tools
        lighting_tool_classes
      end
    end

    # Get OpenRouter tool definitions for a specific persona
    def tool_definitions_for_persona(persona)
      tools_for_persona(persona).map(&:definition)
    end

    # Refresh entity cache (call when entities might have changed)
    def refresh_entity_cache!
      @cube_light_entities = nil
      # Clear tool class caches too
      Tools::Lights::TurnOn.instance_variable_set(:@available_entities, nil)
      Tools::Lights::TurnOff.instance_variable_set(:@available_entities, nil)
      Tools::Lights::SetColorAndBrightness.instance_variable_set(:@available_entities, nil)
      Tools::Lights::SetEffect.instance_variable_set(:@available_entities, nil)
      Tools::Lights::ListEffects.instance_variable_set(:@available_entities, nil)
      Tools::Lights::GetState.instance_variable_set(:@available_entities, nil)
      Tools::HomeAssistant::CallService.instance_variable_set(:@available_domains, nil)
    end
  end
end
