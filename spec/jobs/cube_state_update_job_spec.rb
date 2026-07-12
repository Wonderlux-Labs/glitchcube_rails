# spec/jobs/cube_state_update_job_spec.rb

require 'rails_helper'

RSpec.describe CubeStateUpdateJob, type: :job do
  let(:fake_ha) { FakeHomeAssistant.new }

  before { HomeAssistantService.instance = fake_ha }
  after { HomeAssistantService.reset_instance! }

  describe '#perform' do
    it 'fires the cube_state_update event with speech and inner_monologue' do
      described_class.new.perform(speech: 'Hello there.', inner_monologue: 'I am delighted.')

      event = fake_ha.fired_events.last
      expect(event[:event_type]).to eq('glitchcube_cube_state_update')
      expect(event[:data]).to eq(speech: 'Hello there.', inner_monologue: 'I am delighted.')
    end

    it 'does nothing when both speech and inner_monologue are blank' do
      described_class.new.perform(speech: nil, inner_monologue: '')

      expect(fake_ha.fired_events).to be_empty
    end

    it 'swallows HASS errors so a failed push does not raise' do
      allow(fake_ha).to receive(:fire_event).and_raise(HomeAssistantService::ConnectionError, 'nope')

      expect {
        described_class.new.perform(speech: 'Hello there.', inner_monologue: 'thinking')
      }.not_to raise_error
    end
  end
end
