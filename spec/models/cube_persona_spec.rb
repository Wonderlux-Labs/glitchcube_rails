# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CubePersona, type: :model do
  describe '.current_persona' do
    context 'when Home Assistant is available' do
      before do
        allow(HomeAssistantService).to receive(:entity)
          .with("input_text.current_persona")
          .and_return({ "state" => "buddy" })
      end

      it 'returns the persona from Home Assistant' do
        expect(CubePersona.current_persona).to eq(:buddy)
      end

      it 'caches the result' do
        expect(Rails.cache).to receive(:fetch).with("current_persona").and_return("buddy")
        CubePersona.current_persona
      end
    end

    context 'when Home Assistant is unavailable' do
      before do
        allow(HomeAssistantService).to receive(:entity)
          .with("input_text.current_persona")
          .and_return(nil)
      end

      it 'returns default persona :buddy' do
        expect(CubePersona.current_persona).to eq(:buddy)
      end
    end
  end

  describe '.set_current_persona' do
    it 'accepts valid personas' do
      expect(HomeAssistantService).to receive(:call_service)
        .with("input_text", "set_value", entity_id: "input_text.current_persona", value: "jax")

      expect(Rails.cache).to receive(:write)
        .with("current_persona", "jax", expires_in: 10.minutes)

      CubePersona.set_current_persona(:jax)
    end

    it 'rejects invalid personas' do
      expect(HomeAssistantService).not_to receive(:call_service)

      CubePersona.set_current_persona(:invalid)
    end

    it 'only allows buddy, jax, and zorp' do
      valid_personas = [ :buddy, :jax, :zorp ]
      valid_personas.each do |persona|
        expect(HomeAssistantService).to receive(:call_service)
        CubePersona.set_current_persona(persona)
      end
    end
  end

  describe 'abstract methods' do
    let(:persona) { CubePersona.new }

    it 'requires subclasses to implement persona_id' do
      expect { persona.persona_id }.to raise_error(NotImplementedError)
    end

    it 'requires subclasses to implement name' do
      expect { persona.name }.to raise_error(NotImplementedError)
    end

    it 'requires subclasses to implement process_message' do
      expect { persona.process_message("test") }.to raise_error(NotImplementedError)
    end

    it 'requires subclasses to implement personality_traits' do
      expect { persona.personality_traits }.to raise_error(NotImplementedError)
    end

    it 'requires subclasses to implement knowledge_base' do
      expect { persona.knowledge_base }.to raise_error(NotImplementedError)
    end

    it 'requires subclasses to implement response_style' do
      expect { persona.response_style }.to raise_error(NotImplementedError)
    end

    it 'requires subclasses to implement can_handle_topic?' do
      expect { persona.can_handle_topic?("test") }.to raise_error(NotImplementedError)
    end
  end
end
