# spec/jobs/environment_director_job_spec.rb

require 'rails_helper'

RSpec.describe EnvironmentDirectorJob, type: :job do
  include ActiveJob::TestHelper

  let(:conversation) { create(:conversation) }
  let(:session_id) { conversation.session_id }
  let(:instruction) { 'Turn the lights orange and play heavy metal' }
  let(:user_message) { 'make it spooky' }
  let(:persona) { 'jax' }

  let(:job_params) do
    {
      instruction: instruction,
      session_id: session_id,
      conversation_id: conversation.id,
      user_message: user_message,
      persona: persona
    }
  end

  # The job hands the instruction to a Home Assistant conversation agent. Drive the
  # real path against FakeHomeAssistant and assert on what it was asked to do.
  let(:agent_reply) { 'Done — lights are orange and the metal is blasting.' }
  let(:fake_ha) do
    FakeHomeAssistant.new(
      conversation_response: { 'response' => { 'speech' => { 'plain' => { 'speech' => agent_reply } } } }
    )
  end

  before do
    HomeAssistantService.instance = fake_ha
    allow(Rails.logger).to receive(:info).and_call_original
    allow(Rails.logger).to receive(:error).and_call_original
  end

  after { HomeAssistantService.reset_instance! }

  describe '#perform' do
    it 'sends the instruction to the HA action agent, scoped to the conversation' do
      described_class.new.perform(**job_params)

      request = fake_ha.conversation_requests.last
      expect(request[:text]).to eq(instruction)
      expect(request[:agent_id]).to eq(Rails.configuration.hass_action_agent)
      expect(request[:conversation_id]).to eq("cube_env_#{conversation.id}")
    end

    it 'logs the instruction it is processing' do
      expect(Rails.logger).to receive(:info).with(/EnvironmentDirectorJob.*#{Regexp.escape(instruction)}/)

      described_class.new.perform(**job_params)
    end
  end

  describe 'storing results on the conversation' do
    it "appends a pending_ha_results entry with the agent's reply" do
      described_class.new.perform(**job_params)

      pending = conversation.reload.metadata_json['pending_ha_results']
      expect(pending.length).to eq(1)

      entry = pending.first
      expect(entry['instruction']).to eq(instruction)
      expect(entry['user_message']).to eq(user_message)
      expect(entry['ha_response']).to eq(agent_reply)
      expect(entry['error']).to be_nil
      expect(entry['processed']).to be(false)
      expect(entry['timestamp']).to be_present
    end

    it 'appends to existing pending_ha_results without clobbering prior entries' do
      conversation.update!(metadata_json: { 'pending_ha_results' => [ { 'existing' => true } ] })

      described_class.new.perform(**job_params)

      pending = conversation.reload.metadata_json['pending_ha_results']
      expect(pending.length).to eq(2)
      expect(pending.first).to eq('existing' => true)
      expect(pending.last['instruction']).to eq(instruction)
    end

    it 'does nothing when the conversation cannot be found' do
      params = job_params.merge(conversation_id: -1)

      expect {
        described_class.new.perform(**params)
      }.not_to raise_error
    end
  end

  describe 'error handling' do
    before do
      allow(fake_ha).to receive(:conversation_process).and_raise(StandardError, 'agent boom')
    end

    it 'rescues the error and does not propagate it' do
      expect {
        described_class.new.perform(**job_params)
      }.not_to raise_error
    end

    it 'logs the failure message' do
      expect(Rails.logger).to receive(:error).with(/EnvironmentDirectorJob failed: agent boom/)
      allow(Rails.logger).to receive(:error).with(anything) # backtrace

      described_class.new.perform(**job_params)
    end

    it 'stores a pending_ha_results entry with nil result and the error message' do
      described_class.new.perform(**job_params)

      entry = conversation.reload.metadata_json['pending_ha_results'].first
      expect(entry['ha_response']).to be_nil
      expect(entry['error']).to eq('agent boom')
      expect(entry['instruction']).to eq(instruction)
      expect(entry['user_message']).to eq(user_message)
      expect(entry['processed']).to be(false)
    end
  end

  describe 'job configuration' do
    it 'queues on the default queue' do
      expect(described_class.new.queue_name).to eq('default')
    end

    it 'runs from the enqueued job pipeline' do
      perform_enqueued_jobs do
        described_class.perform_later(**job_params)
      end

      expect(fake_ha.conversation_requests.last[:text]).to eq(instruction)
    end
  end
end
