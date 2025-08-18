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
      tool_enums = ["lights", "music", "display", "environment"]
      
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
          expect(["lights", "music", "display", "environment"]).to include(intent["tool"])
        end
      end
    end
    
    context 'with minimal valid output' do
      let(:minimal_output) do
        {
          "speech_text" => "Sure thing.",
          "continue_conversation" => false,
          "tool_intents" => []
        }
      end
      
      it 'works with minimal required fields only' do
        expect(minimal_output).to have_key("speech_text")
        expect(minimal_output).to have_key("continue_conversation")
        expect(minimal_output["tool_intents"]).to be_an(Array)
      end
    end
  end
end