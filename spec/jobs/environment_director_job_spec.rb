# spec/jobs/environment_director_job_spec.rb

require 'rails_helper'

# The job hands one lane's plain-English instruction to the in-Rails ToolCallingService
# (translator LLM → validated tool calls → HASS), then folds an enriched record —
# narrative + the actual tool_calls and service_calls — into the conversation for the
# next turn. The translator itself is stubbed here; its own spec covers the LLM path.
RSpec.describe EnvironmentDirectorJob, type: :job do
  include ActiveJob::TestHelper

  let(:conversation) { create(:conversation) }
  let(:session_id) { conversation.session_id }
  let(:instruction) { 'lights: bright orange; play heavy metal' }
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

  let(:translator_result) do
    {
      success: true,
      narrative: 'Did: set cube lights',
      tool_calls: [ { name: 'set_cube_lights', arguments: { 'color' => '255,140,0' } } ],
      service_calls: [ { domain: 'script', service: 'turn_on', data: { entity_id: 'script.set_cube_lights' } } ],
      error: nil
    }
  end

  let(:translator) { instance_double(ToolCallingService, execute_intent: translator_result) }

  before do
    allow(ToolCallingService).to receive(:new).and_return(translator)
  end

  describe '#perform' do
    it 'runs the instruction through the translator on the action lane by default' do
      expect(translator).to receive(:execute_intent).with(
        instruction, hash_including(lane: :action, persona: persona)
      ).and_return(translator_result)

      described_class.new.perform(**job_params)
    end

    it 'derives the sound lane from the cube_sound convo_prefix' do
      expect(translator).to receive(:execute_intent).with(
        instruction, hash_including(lane: :sound)
      ).and_return(translator_result)

      described_class.new.perform(**job_params.merge(convo_prefix: 'cube_sound'))
    end

    it 'logs the instruction it is processing' do
      allow(Rails.logger).to receive(:info).and_call_original
      expect(Rails.logger).to receive(:info).with(/EnvironmentDirectorJob.*#{Regexp.escape(instruction)}/)

      described_class.new.perform(**job_params)
    end
  end

  describe 'storing results on the conversation' do
    it 'appends a pending_ha_results entry enriched with tool_calls and service_calls' do
      described_class.new.perform(**job_params)

      pending = conversation.reload.metadata_json['pending_ha_results']
      expect(pending.length).to eq(1)

      entry = pending.first
      expect(entry['instruction']).to eq(instruction)
      expect(entry['user_message']).to eq(user_message)
      expect(entry['ha_response']).to eq('Did: set cube lights')
      expect(entry['tool_calls'].first['name']).to eq('set_cube_lights')
      expect(entry['service_calls'].first['domain']).to eq('script')
      expect(entry['error']).to be_nil
      expect(entry['processed']).to be(false)
      expect(entry['timestamp']).to be_present
    end

    it 'appends without clobbering prior entries' do
      conversation.update!(metadata_json: { 'pending_ha_results' => [ { 'existing' => true } ] })

      described_class.new.perform(**job_params)

      pending = conversation.reload.metadata_json['pending_ha_results']
      expect(pending.length).to eq(2)
      expect(pending.first).to eq('existing' => true)
      expect(pending.last['instruction']).to eq(instruction)
    end

    it 'does nothing when the conversation cannot be found' do
      params = job_params.merge(conversation_id: -1)

      expect { described_class.new.perform(**params) }.not_to raise_error
    end
  end

  describe 'error handling' do
    before do
      allow(translator).to receive(:execute_intent).and_raise(StandardError, 'translator boom')
    end

    it 'rescues the error and does not propagate it' do
      expect { described_class.new.perform(**job_params) }.not_to raise_error
    end

    it 'logs the failure message' do
      allow(Rails.logger).to receive(:error).and_call_original
      expect(Rails.logger).to receive(:error).with(/EnvironmentDirectorJob failed: translator boom/)

      described_class.new.perform(**job_params)
    end

    it 'stores a pending_ha_results entry with the error and no result' do
      described_class.new.perform(**job_params)

      entry = conversation.reload.metadata_json['pending_ha_results'].first
      expect(entry['ha_response']).to be_nil
      expect(entry['error']).to eq('translator boom')
      expect(entry['instruction']).to eq(instruction)
      expect(entry['processed']).to be(false)
    end
  end

  describe 'job configuration' do
    it 'queues on the default queue' do
      expect(described_class.new.queue_name).to eq('default')
    end

    it 'runs from the enqueued job pipeline' do
      expect(translator).to receive(:execute_intent).and_return(translator_result)

      perform_enqueued_jobs { described_class.perform_later(**job_params) }
    end
  end
end
