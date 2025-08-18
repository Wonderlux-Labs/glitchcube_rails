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

        # Music tools
        "play_music" => Tools::Music::PlayMusic,

        # Display tools
        "display_notification" => Tools::Display::Notification,

        # Effects tools
        "control_effects" => Tools::Effects::ControlEffects,

        # Mode control tools
        "mode_control" => Tools::Modes::ModeControl,

        # Communication tools
        "make_announcement" => Tools::Communication::Announcement
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

    # Get tool intent type (query for information vs action for changes)
    def tool_intent(tool_name)
      tool_class = get_tool(tool_name)
      return :unknown unless tool_class

      # Query tools: Get information, sync execution, return data for speech
      # Action tools: Change state, usually async, minimal speech needed
      case tool_name
      when "get_light_state", "list_light_effects"
        :query
      when "turn_on_light", "turn_off_light", "set_light_color_and_brightness", "set_light_effect",
           "play_music", "display_notification", "control_effects",
           "mode_control", "make_announcement"
        :action
      else
        # Default: sync tools are queries, async tools are actions
        tool_class.tool_type == :sync ? :query : :action
      end
    end

    # Categorize tool calls by execution type for conversation orchestrator
    def categorize_tool_calls(tool_calls)
      return { sync_tools: [], async_tools: [], query_tools: [], action_tools: [] } unless tool_calls&.any?

      sync_tools = []
      async_tools = []
      query_tools = []
      action_tools = []

      tool_calls.each do |call|
        tool_name = call.respond_to?(:name) ? call.name : call["name"]
        tool_class = get_tool(tool_name)

        next unless tool_class

        # Categorize by execution type
        case tool_class.tool_type
        when :sync
          sync_tools << call
        when :async
          async_tools << call
        end

        # Categorize by intent
        case tool_intent(tool_name)
        when :query
          query_tools << call
        when :action
          action_tools << call
        end
      end

      {
        sync_tools: sync_tools,
        async_tools: async_tools,
        query_tools: query_tools,
        action_tools: action_tools
      }
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
      # Base tools available to all personas
      base_tool_classes = [
        # Lighting
        Tools::Lights::TurnOn,
        Tools::Lights::TurnOff,
        Tools::Lights::SetColorAndBrightness,
        Tools::Lights::SetEffect,
        Tools::Lights::ListEffects,
        Tools::Lights::GetState,

        # Display
        Tools::Display::Notification,

        # Music
        Tools::Music::PlayMusic,

        # Effects
        Tools::Effects::ControlEffects,

        # Communication
        Tools::Communication::Announcement
      ]

      case persona&.to_s&.downcase
      when "buddy"
        # Buddy gets all tools - enthusiastic and friendly
        base_tool_classes + [ Tools::Modes::ModeControl ]
      when "jax"
        # Jax gets all tools - dramatic and expressive
        base_tool_classes + [ Tools::Modes::ModeControl ]
      when "zorp"
        # Zorp gets all tools - analytical and experimental
        base_tool_classes + [ Tools::Modes::ModeControl ]
      when "lomi"
        # Lomi gets all tools - healing and nurturing
        base_tool_classes + [ Tools::Modes::ModeControl ]
      else
        # Default persona gets all tools
        base_tool_classes + [ Tools::Modes::ModeControl ]
      end
    end

    # Get OpenRouter tool definitions for a specific persona
    def tool_definitions_for_persona(persona)
      tools_for_persona(persona).map(&:definition)
    end

    # Get narrative descriptions for narrative LLM (two-tier architecture)
    def narrative_descriptions_for_persona(persona)
      tools_for_persona(persona).map do |tool_class|
        {
          name: tool_class.name.demodulize.underscore,
          description: tool_class.narrative_desc
        }
      end
    end

    # Get tools for two-tier mode (narrative LLM gets no tools - uses structured output)
    def tools_for_two_tier_mode(persona)
      []
    end

    # Get tool definitions for two-tier mode (technical LLM needs actual tools)
    def tool_definitions_for_two_tier_mode(persona)
      tool_definitions_for_persona(persona)
    end

    # Check if two-tier mode is enabled
    def two_tier_mode_enabled?
      Rails.configuration.try(:two_tier_tools_enabled) || false
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
