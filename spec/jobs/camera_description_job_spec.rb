# spec/jobs/camera_description_job_spec.rb

require 'rails_helper'

RSpec.describe CameraDescriptionJob, type: :job do
  let(:fake_ha) { FakeHomeAssistant.new }
  let(:description) { 'Two people in fuzzy coats, grinning at the cube.' }
  let(:job) { described_class.new }
  let(:snapshot_path) { described_class::SNAPSHOT_DIR.join('snapshot_spec.jpg').to_s }

  before do
    HomeAssistantService.instance = fake_ha
    # Pin the routing flag so specs don't depend on the ambient .env (dev sets
    # USE_LOCAL_VISION=false); the false-path spec overrides this. Stub both backends
    # so no spec makes a real ollama/OpenRouter call.
    allow(Rails.configuration).to receive(:use_local_vision).and_return(true)
    allow(LlmService).to receive(:call_with_local_vision).and_return(description)
    allow(LlmService).to receive(:call_with_vision).and_return(description)

    # Stub the capture: write a fixture JPEG where a real ffmpeg run would land
    # and return its path — the rest of the pipeline runs for real.
    allow(job).to receive(:capture_snapshot!) do
      FileUtils.mkdir_p(described_class::SNAPSHOT_DIR)
      File.binwrite(snapshot_path, "\xFF\xD8\xFF\xD9".b) # minimal JPEG bytes
      snapshot_path
    end
  end

  after do
    HomeAssistantService.reset_instance!
    FileUtils.rm_f(snapshot_path)
  end

  describe '#perform' do
    it 'captures a frame, asks the local vision model, and writes the description to the input_text' do
      job.perform

      expect(LlmService).to have_received(:call_with_local_vision).with(
        prompt: described_class::VISION_PROMPT,
        image_path: snapshot_path
      )

      call = fake_ha.service_calls_for('input_text').last
      expect(call[:service]).to eq('set_value')
      expect(call[:data][:entity_id]).to eq('input_text.current_camera_state')
      expect(call[:data][:value]).to eq(description)
    end

    it 'routes to the OpenRouter vision path when use_local_vision is false' do
      allow(Rails.configuration).to receive(:use_local_vision).and_return(false)

      job.perform

      expect(LlmService).to have_received(:call_with_vision).with(
        prompt: described_class::VISION_PROMPT,
        image_path: snapshot_path
      )
      expect(LlmService).not_to have_received(:call_with_local_vision)
    end

    it 'truncates the description to the input_text max (255 chars)' do
      allow(LlmService).to receive(:call_with_local_vision).and_return('x' * 400)

      job.perform

      value = fake_ha.service_calls_for('input_text').last[:data][:value]
      expect(value.length).to be <= 255
    end
  end

  describe 'throttling (mirrors the old HASS automation debounce)' do
    it 'skips entirely when the current description is non-empty and fresh' do
      fake_ha.set_state('input_text.current_camera_state', 'someone is here',
                        last_updated: 10.seconds.ago.utc.iso8601)

      job.perform

      expect(job).not_to have_received(:capture_snapshot!)
      expect(LlmService).not_to have_received(:call_with_local_vision)
      expect(fake_ha.service_calls_for('input_text')).to be_empty
    end

    it 'refreshes when the current description has gone stale' do
      fake_ha.set_state('input_text.current_camera_state', 'someone was here',
                        last_updated: 10.minutes.ago.utc.iso8601)

      job.perform

      expect(fake_ha.service_calls_for('input_text').last[:data][:value]).to eq(description)
    end

    it 'refreshes immediately when the description is empty, however fresh' do
      fake_ha.set_state('input_text.current_camera_state', '',
                        last_updated: 1.second.ago.utc.iso8601)

      job.perform

      expect(fake_ha.service_calls_for('input_text').last[:data][:value]).to eq(description)
    end

    it 'honors a throttle_seconds override' do
      fake_ha.set_state('input_text.current_camera_state', 'someone is here',
                        last_updated: 5.minutes.ago.utc.iso8601)

      job.perform(throttle_seconds: 3600)

      expect(LlmService).not_to have_received(:call_with_local_vision)
    end
  end

  describe 'disable switches' do
    it 'does nothing when Rails config disables the camera' do
      allow(Rails.configuration).to receive(:disable_camera).and_return(true)

      job.perform

      expect(job).not_to have_received(:capture_snapshot!)
      expect(LlmService).not_to have_received(:call_with_local_vision)
      expect(fake_ha.service_calls_for('input_text')).to be_empty
    end

    it 'does nothing when the HASS disable boolean is on' do
      fake_ha.set_state('input_boolean.disable_camera', 'on')

      job.perform

      expect(job).not_to have_received(:capture_snapshot!)
      expect(LlmService).not_to have_received(:call_with_local_vision)
      expect(fake_ha.service_calls_for('input_text')).to be_empty
    end
  end

  describe 'job configuration' do
    it 'queues on the default queue' do
      expect(job.queue_name).to eq('default')
    end
  end
end
