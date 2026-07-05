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

    it 'exposes exactly the four narrative keys' do
      expect(props.keys).to contain_exactly(:speech, :inner_monologue, :actions, :continue_conversation)
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
