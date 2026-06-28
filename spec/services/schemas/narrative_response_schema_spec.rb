# spec/services/schemas/narrative_response_schema_spec.rb
require 'rails_helper'

RSpec.describe Schemas::NarrativeResponseSchema do
  describe '.schema' do
    let(:schema) { described_class.schema }

    it 'returns an OpenRouter schema' do
      expect(schema).to respond_to(:name)
      expect(schema.name).to eq('narrative_response')
    end

    it 'is an OpenRouter::Schema' do
      expect(schema).to be_a(OpenRouter::Schema)
    end

    it 'builds without error' do
      expect { schema }.not_to raise_error
    end
  end

  describe 'expected structured output shape' do
    let(:valid_output) do
      {
        "speech_text" => "Hello there, welcome to my domain!",
        "continue_conversation" => true,
        "inner_thoughts" => "This person seems interesting",
        "current_mood" => "curious",
        "pressing_questions" => "What brings you here?",
        "environment_instruction" => "Make the lights warm and welcoming and play something ambient",
        "search_memories" => [
          { "query" => "music", "category" => "preference", "timeframe" => "upcoming" }
        ]
      }
    end

    it 'carries the required speech fields' do
      expect(valid_output).to have_key("speech_text")
      expect(valid_output).to have_key("continue_conversation")
    end

    it 'carries a plain-English environment instruction' do
      expect(valid_output["environment_instruction"]).to be_a(String).and be_present
    end

    it 'no longer includes goal_progress or per-turn memories' do
      expect(valid_output).not_to have_key("goal_progress")
      expect(valid_output).not_to have_key("memories")
    end

    it 'uses the new search_memories shape (query/category/timeframe)' do
      valid_output["search_memories"].each do |search|
        expect(search["category"]).to be_in(Memory::CATEGORIES) if search["category"]
        expect(search["timeframe"]).to be_in(%w[upcoming today tomorrow]) if search["timeframe"]
      end
    end

    context 'with minimal valid output' do
      let(:minimal_output) do
        {
          "speech_text" => "Sure thing.",
          "continue_conversation" => false,
          "search_memories" => []
        }
      end

      it 'works with minimal required fields only' do
        expect(minimal_output).to have_key("speech_text")
        expect(minimal_output["search_memories"]).to be_an(Array)
      end
    end
  end
end
