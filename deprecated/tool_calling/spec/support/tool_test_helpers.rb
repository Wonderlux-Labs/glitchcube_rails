# frozen_string_literal: true

module ToolTestHelpers
  # Create a proper mock tool for testing
  def mock_tool(tool_type: :sync, validation_blocks: [])
    double('MockTool',
      tool_type: tool_type,
      validation_blocks: validation_blocks
    )
  end

  # Mock HomeAssistant responses for light tools
  def mock_light_state(entity_id, state_data = {})
    default_state = {
      "state" => "off",
      "attributes" => {}
    }
    allow(HomeAssistantService).to receive(:entity)
      .with(entity_id)
      .and_return(default_state.merge(state_data))
  end

  # Mock the entities list for validation
  def mock_entities(entities = nil)
    entities ||= [
      { "entity_id" => "light.cube_inner" },
      { "entity_id" => "light.cube_voice_ring" },
      { "entity_id" => "light.cube_light_top" }
    ]
    allow(HomeAssistantService).to receive(:entities).and_return(entities)
  end

  def mock_light_with_effects(entity_id, effects = [ "rainbow", "pulse" ])
    mock_light_state(entity_id, {
      "state" => "on",
      "attributes" => {
        "brightness" => 200,
        "rgb_color" => [ 255, 0, 0 ],
        "effect_list" => effects,
        "effect" => effects.first
      }
    })
  end

  def mock_service_call(result = {})
    allow(HomeAssistantService).to receive(:call_service)
      .and_return(result)
  end

  # Create a validated tool call for testing
  def create_validated_tool_call(tool_name, arguments, tool_definition)
    tool_call_data = {
      "id" => "test_#{SecureRandom.uuid}",
      "type" => "function",
      "function" => {
        "name" => tool_name,
        "arguments" => arguments.to_json
      }
    }

    openrouter_call = OpenRouter::ToolCall.new(tool_call_data)
    ValidatedToolCall.new(openrouter_call, tool_definition)
  end
end
