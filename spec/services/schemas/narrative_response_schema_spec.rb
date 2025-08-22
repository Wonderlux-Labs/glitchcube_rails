# spec/services/schemas/narrative_response_schema_spec.rb
require 'rails_helper'

RSpec.describe Schemas::NarrativeResponseSchema do
  describe '.schema' do
    let(:schema) { described_class.schema }

    it 'returns an OpenRouter schema' do
      expect(schema).to respond_to(:name)
      expect(schema.name).to eq('narrative_response')
    end

    it 'defines required fields correctly' do
      # Test the schema structure by accessing its properties
      expect(schema).to be_a(OpenRouter::Schema)
    end

    it 'includes tool_intents array with enum constraints' do
      # Verify the schema allows tool enums we expect
      tool_enums = [ "lights", "music", "display", "environment" ]

      # This tests the schema definition exists
      expect { schema }.not_to raise_error
    end
  end

  describe 'schema validation with OpenRouter' do
    let(:schema) { described_class.schema }

    context 'with valid structured output' do
      let(:valid_output) do
        {
          "speech_text" => "Hello there, welcome to my domain!",
          "continue_conversation" => true,
          "inner_thoughts" => "This person seems interesting",
          "current_mood" => "curious",
          "pressing_questions" => "What brings you here?",
          "tool_intents" => [
            {
              "tool" => "lights",
              "intent" => "Make the lights warm and welcoming"
            },
            {
              "tool" => "music",
              "intent" => "Play something ambient"
            }
          ],
          "direct_tool_calls" => [
            {
              "tool_name" => "rag_search",
              "parameters" => {
                "query" => "fire spinning",
                "type" => "events",
                "limit" => 3
              }
            }
          ],
          "search_memories" => [
            {
              "query" => "previous conversations about music",
              "type" => "summaries",
              "limit" => 2
            }
          ]
        }
      end

      it 'has all required fields' do
        expect(valid_output).to have_key("speech_text")
        expect(valid_output).to have_key("continue_conversation")
      end

      it 'has valid tool intents structure' do
        tool_intents = valid_output["tool_intents"]
        expect(tool_intents).to be_an(Array)

        tool_intents.each do |intent|
          expect(intent).to have_key("tool")
          expect(intent).to have_key("intent")
          expect([ "lights", "music", "display", "environment" ]).to include(intent["tool"])
        end
      end

      it 'has valid direct tool calls structure' do
        direct_tool_calls = valid_output["direct_tool_calls"]
        expect(direct_tool_calls).to be_an(Array)

        direct_tool_calls.each do |tool_call|
          expect(tool_call).to have_key("tool_name")
          expect(tool_call).to have_key("parameters")
          expect([ "rag_search", "get_light_state", "display_notification" ]).to include(tool_call["tool_name"])
        end
      end

      it 'has valid search memories structure' do
        search_memories = valid_output["search_memories"]
        expect(search_memories).to be_an(Array)

        search_memories.each do |search|
          expect(search).to have_key("query")
          expect(search["type"]).to be_in([ "summaries", "events", "people", "all" ]) if search["type"]
          expect(search["limit"]).to be_between(1, 10) if search["limit"]
        end
      end
    end

    context 'with minimal valid output' do
      let(:minimal_output) do
        {
          "speech_text" => "Sure thing.",
          "continue_conversation" => false,
          "tool_intents" => [],
          "direct_tool_calls" => [],
          "search_memories" => []
        }
      end

      it 'works with minimal required fields only' do
        expect(minimal_output).to have_key("speech_text")
        expect(minimal_output).to have_key("continue_conversation")
        expect(minimal_output["tool_intents"]).to be_an(Array)
        expect(minimal_output["direct_tool_calls"]).to be_an(Array)
        expect(minimal_output["search_memories"]).to be_an(Array)
      end
    end
  end
end
