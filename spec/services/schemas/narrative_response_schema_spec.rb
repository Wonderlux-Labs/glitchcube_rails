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

    it 'exposes the narrative keys including the optional urgent_question probe' do
      expect(props.keys).to contain_exactly(:speech, :inner_monologue, :actions, :continue_conversation, :urgent_question)
    end

    it 'types urgent_question as a string' do
      expect(props[:urgent_question][:type]).to eq('string')
    end

    # The DSL marks every field required; optionality in practice comes from
    # strict: false (the model may return it blank/omit it, and we treat blank as
    # "no question" — see LlmIntention#log_urgent_question).
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

    it 'types actions as a list of { action_name, description } objects, both required' do
      actions = props[:actions]
      expect(actions[:type]).to eq('array')

      item = actions[:items]
      expect(item[:type]).to eq('object')
      expect(item[:properties].keys).to contain_exactly(:action_name, :description)
      expect(item[:required]).to contain_exactly('action_name', 'description')
    end
  end
end
