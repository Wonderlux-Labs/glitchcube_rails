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

  # Stub the translator collaborator so no real LLM calls happen.
  let(:tool_calling_service) { instance_double(ToolCallingService) }

  before do
    allow(ToolCallingService).to receive(:new).and_return(tool_calling_service)
    allow(tool_calling_service).to receive(:execute_intent).and_return('adjusting the lighting completed')

    allow(Rails.logger).to receive(:info).and_call_original
    allow(Rails.logger).to receive(:error).and_call_original
  end

  describe '#perform' do
    it 'instantiates ToolCallingService with the session and conversation ids' do
      expect(ToolCallingService).to receive(:new).with(
        session_id: session_id,
        conversation_id: conversation.id
      ).and_return(tool_calling_service)

      described_class.new.perform(**job_params)
    end

    it 'calls execute_intent with the instruction and a context hash of persona + user_message' do
      expect(tool_calling_service).to receive(:execute_intent).with(
        instruction,
        { persona: persona, user_message: user_message }
      )

      described_class.new.perform(**job_params)
    end

    it 'defaults persona to nil in the context when not provided' do
      params = job_params.except(:persona)

      expect(tool_calling_service).to receive(:execute_intent).with(
        instruction,
        { persona: nil, user_message: user_message }
      )

      described_class.new.perform(**params)
    end

    it 'logs the instruction it is processing' do
      expect(Rails.logger).to receive(:info).with(/EnvironmentDirectorJob: #{Regexp.escape(instruction)}/)

      described_class.new.perform(**job_params)
    end
  end

  describe 'storing results on the conversation' do
    it 'appends a pending_ha_results entry with the translator result' do
      described_class.new.perform(**job_params)

      pending = conversation.reload.metadata_json['pending_ha_results']
      expect(pending.length).to eq(1)

      entry = pending.first
      expect(entry['instruction']).to eq(instruction)
      expect(entry['user_message']).to eq(user_message)
      expect(entry['ha_response']).to eq('adjusting the lighting completed')
      expect(entry['error']).to be_nil
      expect(entry['processed']).to be(false)
      expect(entry['timestamp']).to be_present
    end

    it 'appends to existing pending_ha_results without clobbering prior entries' do
      conversation.update!(metadata_json: { 'pending_ha_results' => [{ 'existing' => true }] })

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
      allow(tool_calling_service).to receive(:execute_intent)
        .and_raise(StandardError, 'translator boom')
    end

    it 'rescues the error and does not propagate it' do
      expect {
        described_class.new.perform(**job_params)
      }.not_to raise_error
    end

    it 'logs the failure message and a backtrace' do
      expect(Rails.logger).to receive(:error).with(/EnvironmentDirectorJob failed: translator boom/)
      expect(Rails.logger).to receive(:error).with(anything) # backtrace

      described_class.new.perform(**job_params)
    end

    it 'stores a pending_ha_results entry with nil result and the error message' do
      described_class.new.perform(**job_params)

      entry = conversation.reload.metadata_json['pending_ha_results'].first
      expect(entry['ha_response']).to be_nil
      expect(entry['error']).to eq('translator boom')
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
      expect(tool_calling_service).to receive(:execute_intent)

      perform_enqueued_jobs do
        described_class.perform_later(**job_params)
      end
    end
  end
end
