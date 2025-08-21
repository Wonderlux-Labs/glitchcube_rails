# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Tool array parameter validation", type: :service do
  describe "array parameters in tool definitions" do
    it "should have valid JSON Schema format for all array parameters" do
      # Get all tool definitions
      all_tools = Tools::Registry.all_tools

      all_tools.each do |tool_name, tool_class|
        tool_definition = tool_class.definition
        parameters = tool_definition.to_h.dig("function", "parameters", "properties") || {}

        parameters.each do |param_name, param_def|
          if param_def["type"] == "array"
            # Arrays must have items specification for valid JSON Schema
            expect(param_def).to have_key("items"),
              "Tool '#{tool_name}' parameter '#{param_name}' is an array but missing 'items' specification. " \
              "This causes OpenRouter API to reject the tool definition with 'Bad Request: Provider returned error'."

            # Items should be a valid schema object
            items = param_def["items"]
            expect(items).to be_a(Hash),
              "Tool '#{tool_name}' parameter '#{param_name}' has invalid 'items' - must be a schema object"

            expect(items).to have_key("type"),
              "Tool '#{tool_name}' parameter '#{param_name}' items must specify a 'type'"
          end
        end
      end
    end
  end

  describe "OpenRouter API compatibility" do
    it "should successfully call OpenRouter with SetState tool (the main fix)", :vcr do
      # Test the specific tool that was originally failing
      tool_definition = Tools::Lights::SetState.definition

      expect {
        client = OpenRouter::Client.new

        # Make a minimal API call to validate the tool definition
        client.complete(
          [ { role: "user", content: "Turn on lights with red color" } ],
          model: "openai/gpt-5-mini",
          tools: [ tool_definition ],
          tool_choice: "auto",
          extras: { temperature: 0.1, max_tokens: 50 }
        )
      }.not_to raise_error, "SetState tool definition should work with items specification for rgb_color array"
    end
  end
end
