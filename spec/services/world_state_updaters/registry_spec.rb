# spec/services/world_state_updaters/registry_spec.rb
#
# SECURITY-CRITICAL: This registry is an explicit allowlist that replaced an
# unsafe `constantize` lookup on the Home Assistant-facing world-state trigger
# endpoint. The previous implementation could resolve and invoke arbitrary
# classes from attacker-controlled input. These specs lock in the allowlist
# behavior so that guarantee cannot silently regress.

require 'rails_helper'

RSpec.describe WorldStateUpdaters::Registry do
  describe '.fetch' do
    context 'with allowlisted names' do
      it 'resolves "BackendHealthService" to the correct service class' do
        expect(described_class.fetch('BackendHealthService'))
          .to eq(WorldStateUpdaters::BackendHealthService)
      end

      it 'resolves "WeatherForecastSummarizerService" to the correct service class' do
        expect(described_class.fetch('WeatherForecastSummarizerService'))
          .to eq(WorldStateUpdaters::WeatherForecastSummarizerService)
      end

      it 'returns classes that actually respond to .call (the trigger contract)' do
        described_class.names.each do |name|
          expect(described_class.fetch(name)).to respond_to(:call)
        end
      end

      it 'coerces non-string (symbol) input to a string before lookup' do
        expect(described_class.fetch(:BackendHealthService))
          .to eq(WorldStateUpdaters::BackendHealthService)
      end
    end

    context 'with unregistered names' do
      it 'returns nil for an unknown name (does not raise)' do
        expect(described_class.fetch('TotallyUnknownService')).to be_nil
      end

      it 'returns nil for a blank string' do
        expect(described_class.fetch('')).to be_nil
      end

      it 'returns nil for nil (coerced to empty string)' do
        expect(described_class.fetch(nil)).to be_nil
      end
    end

    context 'security: does not allow arbitrary constantization' do
      # The whole point of the registry. Each of these is a string that WOULD
      # have resolved to a real, callable class under the old `constantize`
      # implementation. They must all be rejected because they are not on the
      # allowlist.

      it 'rejects a real, fully-qualified service class name that is not allowlisted' do
        # ReflectionService is a real, callable service, intentionally not on the
        # world-state trigger allowlist.
        expect(defined?(ReflectionService)).to be_truthy
        expect(described_class.fetch('ReflectionService')).to be_nil
      end

      it 'rejects NarrativeConversationSyncService (real class, not on allowlist)' do
        expect(defined?(WorldStateUpdaters::NarrativeConversationSyncService)).to be_truthy
        expect(described_class.fetch('NarrativeConversationSyncService')).to be_nil
      end

      it 'rejects a dangerous core class name' do
        expect(described_class.fetch('Kernel')).to be_nil
        expect(described_class.fetch('Object')).to be_nil
        expect(described_class.fetch('File')).to be_nil
      end

      it 'never returns a class that is not one of the explicitly allowlisted classes' do
        allowed = [
          WorldStateUpdaters::BackendHealthService,
          WorldStateUpdaters::WeatherForecastSummarizerService
        ]

        %w[
          ReflectionService
          PromptService
          NarrativeConversationSyncService
          Kernel Object File HomeAssistantService User
        ].each do |name|
          result = described_class.fetch(name)
          expect(result).to be_nil.or(satisfy { |r| allowed.include?(r) })
          expect(result).to be_nil
        end
      end
    end
  end

  describe '.names' do
    it 'returns the list of allowlisted names' do
      expect(described_class.names)
        .to contain_exactly('BackendHealthService', 'WeatherForecastSummarizerService')
    end

    it 'returns only strings' do
      expect(described_class.names).to all(be_a(String))
    end

    it 'every advertised name resolves back to a class via .fetch' do
      described_class.names.each do |name|
        expect(described_class.fetch(name)).to be_a(Class)
      end
    end
  end

  describe 'TRIGGERABLE constant' do
    it 'is frozen so the allowlist cannot be mutated at runtime' do
      expect(described_class::TRIGGERABLE).to be_frozen
    end

    it 'maps each allowlisted string key to its corresponding class' do
      expect(described_class::TRIGGERABLE).to eq(
        'BackendHealthService' => WorldStateUpdaters::BackendHealthService,
        'WeatherForecastSummarizerService' => WorldStateUpdaters::WeatherForecastSummarizerService
      )
    end
  end
end
