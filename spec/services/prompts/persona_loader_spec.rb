# spec/services/prompts/persona_loader_spec.rb
require 'rails_helper'

RSpec.describe Prompts::PersonaLoader do
  describe '.load' do
    it 'loads the correct persona class for buddy' do
      result = described_class.load('buddy')
      expect(result).to be_instance_of(Personas::BuddyPersona)
    end

    it 'loads the correct persona class for jax' do
      result = described_class.load('jax')
      expect(result).to be_instance_of(Personas::JaxPersona)
    end

    it 'handles string inputs' do
      result = described_class.load('sparkle')
      expect(result).to be_instance_of(Personas::SparklePersona)
    end

    it 'handles symbol inputs' do
      result = described_class.load(:zorp)
      expect(result).to be_instance_of(Personas::ZorpPersona)
    end

    it 'handles case insensitive inputs' do
      result = described_class.load('LOMI')
      expect(result).to be_instance_of(Personas::LomiPersona)
    end

    context 'when persona is unknown' do
      before do
        allow(Rails.logger).to receive(:warn)
      end

      it 'defaults to buddy persona' do
        result = described_class.load('unknown_persona')
        expect(result).to be_instance_of(Personas::BuddyPersona)
      end

      it 'logs a warning' do
        expect(Rails.logger).to receive(:warn).with(/Unknown persona: unknown_persona/)
        described_class.load('unknown_persona')
      end
    end

    context 'when persona is nil' do
      before do
        allow(Rails.logger).to receive(:warn)
      end

      it 'defaults to buddy persona' do
        result = described_class.load(nil)
        expect(result).to be_instance_of(Personas::BuddyPersona)
      end
    end

    context 'when persona is empty string' do
      before do
        allow(Rails.logger).to receive(:warn)
      end

      it 'defaults to buddy persona' do
        result = described_class.load('')
        expect(result).to be_instance_of(Personas::BuddyPersona)
      end
    end
  end

  describe 'PERSONA_MAPPING' do
    it 'includes all expected personas' do
      expected_personas = %w[buddy jax sparkle zorp lomi crash neon mobius thecube]
      expect(described_class::PERSONA_MAPPING.keys).to contain_exactly(*expected_personas)
    end

    it 'maps to the correct persona classes' do
      expect(described_class::PERSONA_MAPPING['buddy']).to eq(Personas::BuddyPersona)
      expect(described_class::PERSONA_MAPPING['jax']).to eq(Personas::JaxPersona)
      expect(described_class::PERSONA_MAPPING['sparkle']).to eq(Personas::SparklePersona)
    end
  end
end
