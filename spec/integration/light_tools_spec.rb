# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Light Tools Integration", type: :integration do
  include ToolTestHelpers

  let(:test_entity) { "light.cube_inner" }

  describe Tools::Lights::GetState do
    describe "#call" do
      it "includes available effects in response" do
        # Mock HomeAssistant responses
        mock_entities
        mock_light_with_effects(test_entity, [ "rainbow", "pulse", "strobe", "fade" ])

        tool = Tools::Lights::GetState.new
        result = tool.call(entity_id: test_entity)

        expect(result[:success]).to be true
        expect(result[:available_effects]).to eq([ "rainbow", "pulse", "strobe", "fade" ])
        expect(result[:effects_count]).to eq(4)
        expect(result[:effect]).to eq("rainbow")
      end

      it "handles lights without effects gracefully" do
        mock_entities
        mock_light_state(test_entity, {
          "state" => "off",
          "attributes" => {}
        })

        tool = Tools::Lights::GetState.new
        result = tool.call(entity_id: test_entity)

        expect(result[:success]).to be true
        expect(result[:available_effects]).to eq([])
        expect(result[:effects_count]).to eq(0)
      end
    end

    describe "validation" do
      it "validates entity_id with helpful messages" do
        tool_definition = Tools::Lights::GetState.definition
        validated_call = create_validated_tool_call(
          "get_light_state",
          { entity_id: "light.invalid" },
          tool_definition
        )

        expect(validated_call).not_to be_valid
        error_message = validated_call.validation_errors.first
        expect(error_message).to include("Available cube lights:")
        expect(error_message).to include("light.cube_inner")
      end
    end
  end

  describe Tools::Lights::SetState do
    describe "#call" do
      it "handles unified state setting" do
        mock_entities
        mock_service_call({})

        tool = Tools::Lights::SetState.new
        result = tool.call(
          entity_id: test_entity,
          state: "on",
          brightness: 75,
          rgb_color: [ 255, 128, 0 ]
        )

        expect(result[:success]).to be true
        expect(result[:changes_applied]).to include("brightness: 75%")
        expect(result[:changes_applied]).to include("color: RGB(255, 128, 0)")
      end

      it "handles turning off lights" do
        mock_entities
        mock_service_call({})

        tool = Tools::Lights::SetState.new
        result = tool.call(entity_id: test_entity, state: "off")

        expect(result[:success]).to be true
        expect(result[:state]).to eq('off')
      end

      it "requires at least one parameter" do
        mock_entities

        tool = Tools::Lights::SetState.new
        result = tool.call(entity_id: test_entity)

        expect(result[:success]).to be false
        expect(result[:error]).to include("Must specify at least one parameter")
        expect(result[:examples]).to be_present
      end
    end

    describe "validation" do
      it "validates RGB color with helpful examples" do
        tool_definition = Tools::Lights::SetState.definition
        validated_call = create_validated_tool_call(
          "set_light_state",
          { entity_id: test_entity, rgb_color: [ 256, 0, 0 ] },
          tool_definition
        )

        expect(validated_call).not_to be_valid
        error_message = validated_call.validation_errors.first
        expect(error_message).to include("RGB values must be integers 0-255")
        expect(error_message).to include("Invalid values: [256]")
      end

      it "provides logical validation for off state" do
        tool_definition = Tools::Lights::SetState.definition
        validated_call = create_validated_tool_call(
          "set_light_state",
          {
            entity_id: test_entity,
            state: "off",
            brightness: 50
          },
          tool_definition
        )

        expect(validated_call).not_to be_valid
        expect(validated_call.validation_errors).to include(
          "Cannot set brightness, color, or effects when turning light off. Use state: 'on' instead."
        )
      end

      it "provides smart suggestions for black color" do
        tool_definition = Tools::Lights::SetState.definition
        validated_call = create_validated_tool_call(
          "set_light_state",
          { entity_id: test_entity, rgb_color: [ 0, 0, 0 ] },
          tool_definition
        )

        expect(validated_call).not_to be_valid
        expect(validated_call.validation_errors).to include(
          "RGB [0, 0, 0] is black (no light). Did you mean to set state: 'off' instead?"
        )
      end
    end
  end

  private

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
