# spec/services/prompts/persona_loader_spec.rb
require 'rails_helper'

RSpec.describe Prompts::PersonaLoader do
  describe '.load' do
    it 'maps a persona name to its class (case-insensitive)' do
      expect(described_class.load('buddy')).to be_instance_of(Personas::BuddyPersona)
      expect(described_class.load(:jax)).to be_instance_of(Personas::JaxPersona)
      expect(described_class.load('ZORP')).to be_instance_of(Personas::ZorpPersona)
    end

    it 'defaults to buddy for unknown, nil, or blank input' do
      expect(described_class.load('nope')).to be_instance_of(Personas::BuddyPersona)
      expect(described_class.load(nil)).to be_instance_of(Personas::BuddyPersona)
      expect(described_class.load('')).to be_instance_of(Personas::BuddyPersona)
    end
  end

  describe '.voice_id_for' do
    it 'returns the persona voice id' do
      expect(described_class.voice_id_for('buddy')).to eq(Personas::BuddyPersona.new.voice_id)
    end
  end
end
