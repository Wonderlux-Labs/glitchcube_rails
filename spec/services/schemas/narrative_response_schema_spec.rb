# spec/services/schemas/narrative_response_schema_spec.rb
require 'rails_helper'

RSpec.describe Schemas::NarrativeResponseSchema do
  describe '.schema' do
    let(:schema) { described_class.schema }

    it 'returns an OpenRouter::Schema named narrative_response' do
      expect(schema).to be_a(OpenRouter::Schema)
      expect(schema.name).to eq('narrative_response')
    end

    it 'builds without error' do
      expect { schema }.not_to raise_error
    end
  end

  describe 'the emitted JSON schema shape' do
    let(:props) { described_class.schema.to_h.dig(:schema, :properties) }

    it 'exposes the narrative keys, the optional action channels, and ooc_questions' do
      expect(props.keys).to contain_exactly(
        :speech, :inner_monologue, :lights, :sound, :marquee, :other_actions,
        :continue_conversation, :ooc_questions
      )
    end

    it 'types ooc_questions as a string' do
      expect(props[:ooc_questions][:type]).to eq('string')
    end

    # The DSL marks every field required; optionality in practice comes from
    # strict: false (the model may return it blank/omit it, and we treat blank as
    # "no question" — see LlmIntention#log_ooc_questions).
    it 'is non-strict so optional fields can be left blank' do
      expect(described_class.schema.to_h[:strict]).to be(false)
    end

    it 'types speech and inner_monologue as strings' do
      expect(props[:speech][:type]).to eq('string')
      expect(props[:inner_monologue][:type]).to eq('string')
    end

    it 'types continue_conversation as boolean' do
      expect(props[:continue_conversation][:type]).to eq('boolean')
    end

    it 'types the action channels as optional strings' do
      %i[lights sound marquee other_actions].each do |channel|
        expect(props[channel][:type]).to eq('string'), "expected #{channel} to be a string"
      end
    end
  end
end
