# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ValidatedToolCall do
  let(:openrouter_tool_call) do
    tool_call_data = {
      "id" => "call_123",
      "type" => "function",
      "function" => {
        "name" => "test_tool",
        "arguments" => '{"entity_id": "light.cube_inner", "brightness": 80}'
      }
    }
    OpenRouter::ToolCall.new(tool_call_data)
  end

  let(:mock_tool_definition) do
    double('ToolDefinition', validation_blocks: [])
  end

  describe '#initialize' do
    it 'wraps an OpenRouter::ToolCall successfully' do
      validated_call = ValidatedToolCall.new(openrouter_tool_call, mock_tool_definition)

      expect(validated_call.name).to eq('test_tool')
      expect(validated_call.id).to eq('call_123')
      expect(validated_call.arguments).to eq({ "entity_id" => "light.cube_inner", "brightness" => 80 })
    end

    it 'raises error for non-ToolCall objects' do
      expect {
        ValidatedToolCall.new("not a tool call", mock_tool_definition)
      }.to raise_error(ArgumentError, /Expected OpenRouter::ToolCall/)
    end
  end

  describe '#valid?' do
    context 'with no validation blocks' do
      it 'is valid by default' do
        validated_call = ValidatedToolCall.new(openrouter_tool_call, mock_tool_definition)
        expect(validated_call).to be_valid
      end
    end

    context 'with validation blocks' do
      let(:validation_block) do
        proc do |params, errors|
          if params["brightness"] && params["brightness"] < 10
            errors << "Brightness too low"
          end
        end
      end

      let(:tool_with_validation) do
        double('ToolDefinition', validation_blocks: [ validation_block ])
      end

      it 'runs validation and passes when valid' do
        validated_call = ValidatedToolCall.new(openrouter_tool_call, tool_with_validation)
        expect(validated_call).to be_valid
        expect(validated_call.validation_errors).to be_empty
      end

      it 'runs validation and fails when invalid' do
        low_brightness_data = {
          "id" => "call_123",
          "type" => "function",
          "function" => {
            "name" => "test_tool",
            "arguments" => '{"brightness": 5}'
          }
        }
        low_brightness_call = OpenRouter::ToolCall.new(low_brightness_data)
        validated_call = ValidatedToolCall.new(low_brightness_call, tool_with_validation)

        expect(validated_call).not_to be_valid
        expect(validated_call.validation_errors).to include("Brightness too low")
      end
    end
  end

  describe '#validation_errors' do
    it 'caches validation results' do
      validation_block = proc { |params, errors| errors << "Always invalid" }
      tool_def = double('ToolDefinition', validation_blocks: [ validation_block ])
      validated_call = ValidatedToolCall.new(openrouter_tool_call, tool_def)

      # First call runs validation
      errors1 = validated_call.validation_errors
      expect(errors1).to include("Always invalid")

      # Second call should return cached result
      errors2 = validated_call.validation_errors
      expect(errors2).to be(errors1) # Same object
    end

    it 'handles validation block errors gracefully' do
      failing_validation = proc { |params, errors| raise "Validation failed" }
      tool_def = double('ToolDefinition', validation_blocks: [ failing_validation ])
      validated_call = ValidatedToolCall.new(openrouter_tool_call, tool_def)

      expect(validated_call.validation_errors).to include(/Internal validation error/)
    end
  end

  describe '#reset_validation!' do
    it 'clears cached validation results' do
      validation_block = proc { |params, errors| errors << "Error" }
      tool_def = double('ToolDefinition', validation_blocks: [ validation_block ])
      validated_call = ValidatedToolCall.new(openrouter_tool_call, tool_def)

      # Get errors to cache them
      validated_call.validation_errors
      expect(validated_call).not_to be_valid

      # Reset and check again
      validated_call.reset_validation!
      # This would still fail because the validation block still adds an error
      expect(validated_call.validation_errors).to include("Error")
    end
  end

  describe '.from_tool_call_data' do
    it 'creates ValidatedToolCall from tool call data' do
      tool_call_data = {
        "id" => "call_456",
        "type" => "function",
        "function" => {
          "name" => "another_tool",
          "arguments" => '{"param": "value"}'
        }
      }

      validated_call = ValidatedToolCall.from_tool_call_data(tool_call_data, mock_tool_definition)

      expect(validated_call.name).to eq('another_tool')
      expect(validated_call.id).to eq('call_456')
      expect(validated_call.arguments).to eq({ "param" => "value" })
    end
  end

  describe '#same_call_as?' do
    it 'identifies same calls correctly' do
      call1 = ValidatedToolCall.new(openrouter_tool_call, mock_tool_definition)
      call2 = ValidatedToolCall.new(openrouter_tool_call, mock_tool_definition)

      expect(call1.same_call_as?(call2)).to be true
    end

    it 'identifies different calls correctly' do
      different_data = {
        "id" => "call_different",
        "type" => "function",
        "function" => {
          "name" => "different_tool",
          "arguments" => '{}'
        }
      }
      different_call = OpenRouter::ToolCall.new(different_data)

      call1 = ValidatedToolCall.new(openrouter_tool_call, mock_tool_definition)
      call2 = ValidatedToolCall.new(different_call, mock_tool_definition)

      expect(call1.same_call_as?(call2)).to be false
    end
  end

  describe 'delegation to OpenRouter::ToolCall' do
    let(:validated_call) { ValidatedToolCall.new(openrouter_tool_call, mock_tool_definition) }

    it 'delegates core methods correctly' do
      expect(validated_call.id).to eq(openrouter_tool_call.id)
      expect(validated_call.name).to eq(openrouter_tool_call.name)
      expect(validated_call.arguments).to eq(openrouter_tool_call.arguments)
      expect(validated_call.function_name).to eq(openrouter_tool_call.function_name)
    end

    it 'delegates to_result_message correctly' do
      result = { success: true, message: "Test result" }

      expect(validated_call.to_result_message(result)).to eq(
        openrouter_tool_call.to_result_message(result)
      )
    end
  end
end
