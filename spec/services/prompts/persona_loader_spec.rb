# spec/services/prompts/persona_loader_spec.rb
require 'rails_helper'

RSpec.describe Prompts::PersonaLoader do
  describe '.load' do
    it 'always returns the artifact persona, whatever name is passed' do
      expect(described_class.load('buddy')).to be_instance_of(Personas::ArtifactPersona)
      expect(described_class.load(:jax)).to be_instance_of(Personas::ArtifactPersona)
      expect(described_class.load('anything')).to be_instance_of(Personas::ArtifactPersona)
    end

    it 'returns the artifact persona for nil and empty input' do
      expect(described_class.load(nil)).to be_instance_of(Personas::ArtifactPersona)
      expect(described_class.load('')).to be_instance_of(Personas::ArtifactPersona)
      expect(described_class.load).to be_instance_of(Personas::ArtifactPersona)
    end
  end

  describe '.voice_id_for' do
    it 'returns the artifact voice id' do
      expect(described_class.voice_id_for('anything')).to eq(Personas::ArtifactPersona.new.voice_id)
    end
  end
end
