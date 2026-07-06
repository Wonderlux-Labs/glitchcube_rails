# spec/services/prompts/context_builder_spec.rb
require 'rails_helper'

RSpec.describe Prompts::ContextBuilder do
  before { allow(HomeAssistantService).to receive(:entity).and_return(nil) }

  describe '.build' do
    it 'delegates to the instance' do
      expect_any_instance_of(described_class).to receive(:build).and_return("ctx")
      expect(described_class.build(persona: "buddy")).to eq("ctx")
    end
  end

  describe '#build' do
    subject { described_class.new(persona: persona_slug).build }
    let(:persona_slug) { nil }

    context 'world state' do
      it 'injects the world-state sensor content verbatim' do
        allow(HomeAssistantService).to receive(:entity).with("sensor.glitchcube_world_state")
          .and_return({ "attributes" => { "content" => "It is 12:55 AM and it is dark out." } })
        expect(subject).to include("Right now: It is 12:55 AM and it is dark out.")
      end

      it 'fails open when the fetch raises' do
        allow(HomeAssistantService).to receive(:entity).with("sensor.glitchcube_world_state")
          .and_raise(StandardError, "HASS down")
        expect(Rails.logger).to receive(:warn).with(/Could not load sensor.glitchcube_world_state/)
        expect { subject }.not_to raise_error
      end
    end

    context 'overall memory' do
      it 'injects the latest overall summary' do
        create(:summary, summary_type: 'overall', summary_text: 'The whole night has been rowdy.', created_at: 1.minute.ago)
        expect(subject).to include("The bigger picture")
        expect(subject).to include("The whole night has been rowdy.")
      end

      it 'injects the cross-persona director note and pending visitor threads when present' do
        create(:summary, summary_type: 'overall', summary_text: 'A rowdy night.',
               metadata: { director_note: 'Devices are failing across the board.',
                           active_threads: 'Laurie is back at midnight for a reading.' }.to_json,
               created_at: 1.minute.ago)

        expect(subject).to include("A note to all of the cube's personas right now: Devices are failing across the board.")
        expect(subject).to include("Still in the air (things visitors set up that you can pick up): Laurie is back at midnight for a reading.")
      end
    end

    context 'persona memory' do
      let(:persona_slug) { "zorp" }
      let!(:zorp) { Persona.create!(slug: "zorp", name: "Zorp") }

      it 'injects the current persona summary and its self-steering note' do
        create(:summary, persona: zorp, summary_type: 'persona',
               summary_text: 'You did a lot of cosmic readings.',
               metadata: { ooc_note: 'Ease off the butt-readings.' }.to_json,
               created_at: 1.minute.ago)

        expect(subject).to include("What you (Zorp) remember")
        expect(subject).to include("You did a lot of cosmic readings.")
        expect(subject).to include("A note to yourself: Ease off the butt-readings.")
      end

      it 'injects nothing persona-specific when no persona is given' do
        create(:summary, persona: zorp, summary_type: 'persona', summary_text: 'zorp memory', created_at: 1.minute.ago)
        result = described_class.new(persona: nil).build
        expect(result).not_to include("remember from your recent time")
      end
    end

    context 'running memory' do
      it 'injects the latest interaction summary and its real-world facts' do
        create(:summary, summary_type: 'interaction', summary_text: 'busy night',
               metadata: { real_world_facts: 'Dance party at the Corral at 2am.' }.to_json,
               created_at: 1.minute.ago)
        expect(subject).to include("Recently (your running memory")
        expect(subject).to include("Things you've picked up about tonight: Dance party at the Corral at 2am.")
      end
    end

    it 'returns an empty string when nothing is available' do
      expect(subject).to eq("")
    end
  end
end
