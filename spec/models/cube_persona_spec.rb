# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CubePersona, type: :model do
  describe '.current_persona' do
    it 'reads the current persona from Home Assistant' do
      allow(HomeAssistantService).to receive(:entity)
        .with("input_select.current_persona")
        .and_return({ "state" => "jax" })

      expect(CubePersona.current_persona).to eq(:jax)
    end

    it 'falls back to a valid roster persona when HA is unavailable' do
      allow(HomeAssistantService).to receive(:entity).and_return(nil)
      Rails.cache.delete("current_persona")

      expect(CubePersona::PERSONAS).to include(CubePersona.current_persona)
    end
  end

  describe 'PERSONAS' do
    it 'is the fun persona roster' do
      expect(CubePersona::PERSONAS).to match_array(
        %i[thecube buddy neon sparkle zorp crash jax mobius]
      )
    end
  end

  describe '.set_current_persona' do
    before do
      allow(HomeAssistantService).to receive(:call_service)
      allow(HomeAssistantService).to receive(:entity)
        .with("input_select.current_persona")
        .and_return({ "state" => "buddy" })
      allow(PersonaSwitchService).to receive(:handle_persona_switch)
    end

    it 'writes the input_select directly and enqueues the grand entrance show for :grand' do
      expect {
        CubePersona.set_current_persona(:jax, entrance: :grand)
      }.to have_enqueued_job(ShowJob).with("grand_entrance", persona: "jax")

      expect(HomeAssistantService).to have_received(:call_service).with(
        "input_select", "select_option",
        entity_id: "input_select.current_persona", option: "jax"
      )
    end

    it 'uses the quick HASS script for :quick, with no show' do
      expect {
        CubePersona.set_current_persona(:jax, entrance: :quick)
      }.not_to have_enqueued_job(ShowJob)

      expect(HomeAssistantService).to have_received(:call_service)
        .with("script", "set_persona_quick", persona: "jax")
    end
  end

  describe 'abstract interface' do
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
