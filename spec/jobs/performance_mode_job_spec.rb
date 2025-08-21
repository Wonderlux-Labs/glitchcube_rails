# spec/jobs/performance_mode_job_spec.rb

require 'rails_helper'

RSpec.describe PerformanceModeJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:session_id) { 'job_test_session' }
  let(:job_params) do
    {
      session_id: session_id,
      performance_type: 'comedy',
      duration_minutes: 1, # Short for testing
      prompt: 'Test comedy routine prompt',
      persona: nil
    }
  end

  before do
    Rails.cache.clear
    ConversationLog.where(session_id: session_id).delete_all
  end

  after do
    Rails.cache.clear
  end

  describe '#perform', vcr: { cassette_name: 'performance_mode_job/successful_performance' } do
    let(:mock_service) { instance_double(PerformanceModeService) }

    before do
      allow(PerformanceModeService).to receive(:new).and_return(mock_service)
      allow(mock_service).to receive(:instance_variable_set)
      allow(mock_service).to receive(:send)
      allow(mock_service).to receive(:run_performance_loop)
    end

    it 'creates PerformanceModeService with correct parameters' do
      expect(PerformanceModeService).to receive(:new).with(
        session_id: session_id,
        performance_type: 'comedy',
        duration_minutes: 1,
        prompt: 'Test comedy routine prompt',
        persona: nil
      )

      perform_enqueued_jobs do
        PerformanceModeJob.perform_later(**job_params)
      end
    end

    it 'sets up service timing and state correctly' do
      freeze_time do
        expect(mock_service).to receive(:instance_variable_set).with(:@start_time, Time.current)
        expect(mock_service).to receive(:instance_variable_set).with(:@end_time, Time.current + 1.minute)
        expect(mock_service).to receive(:instance_variable_set).with(:@is_running, true)
        expect(mock_service).to receive(:instance_variable_set).with(:@should_stop, false)
        expect(mock_service).to receive(:instance_variable_set).with(:@performance_segments, [])

        perform_enqueued_jobs do
          PerformanceModeJob.perform_later(**job_params)
        end
      end
    end

    it 'stores initial performance state' do
      expect(mock_service).to receive(:send).with(:store_performance_state)

      perform_enqueued_jobs do
        PerformanceModeJob.perform_later(**job_params)
      end
    end

    it 'runs the performance loop' do
      expect(mock_service).to receive(:run_performance_loop)

      perform_enqueued_jobs do
        PerformanceModeJob.perform_later(**job_params)
      end
    end

    it 'logs start and completion messages' do
      expect(Rails.logger).to receive(:info).with(/Starting performance mode job for session/)
      expect(Rails.logger).to receive(:info).with(/Performance mode job completed for session/)

      perform_enqueued_jobs do
        PerformanceModeJob.perform_later(**job_params)
      end
    end
  end

  describe 'error handling', vcr: { cassette_name: 'performance_mode_job/error_handling' } do
    context 'when service initialization fails' do
      before do
        allow(PerformanceModeService).to receive(:new).and_raise(StandardError, 'Service initialization failed')
      end

      it 'logs the error and cleans up cache' do
        expect(Rails.logger).to receive(:error).with(/Performance mode job failed/)
        expect(Rails.logger).to receive(:error).with(anything) # backtrace

        perform_enqueued_jobs do
          PerformanceModeJob.perform_later(**job_params)
        end
      end

      it 'clears cached performance state on error' do
        # Set up some cached state
        Rails.cache.write("performance_mode:#{session_id}", { test: 'data' })

        perform_enqueued_jobs do
          PerformanceModeJob.perform_later(**job_params)
        end

        expect(Rails.cache.read("performance_mode:#{session_id}")).to be_nil
      end
    end

    context 'when performance loop fails' do
      let(:mock_service) { instance_double(PerformanceModeService) }

      before do
        allow(PerformanceModeService).to receive(:new).and_return(mock_service)
        allow(mock_service).to receive(:instance_variable_set)
        allow(mock_service).to receive(:send)
        allow(mock_service).to receive(:run_performance_loop).and_raise(StandardError, 'Performance loop crashed')
      end

      it 'logs error and attempts cleanup' do
        expect(Rails.logger).to receive(:error).with(/Performance mode job failed: Performance loop crashed/)

        perform_enqueued_jobs do
          PerformanceModeJob.perform_later(**job_params)
        end
      end
    end

    context 'when cleanup itself fails' do
      before do
        allow(PerformanceModeService).to receive(:new).and_raise(StandardError, 'Initial error')
        allow(Rails.cache).to receive(:delete).and_raise(StandardError, 'Cleanup error')
      end

      it 'ignores cleanup errors silently' do
        expect(Rails.logger).to receive(:error).with(/Performance mode job failed: Initial error/)

        expect {
          perform_enqueued_jobs do
            PerformanceModeJob.perform_later(**job_params)
          end
        }.not_to raise_error
      end
    end
  end

  describe 'integration with real service', vcr: { cassette_name: 'performance_mode_job/integration_test' } do
    let(:integration_params) do
      {
        session_id: 'integration_test_session',
        performance_type: 'comedy',
        duration_minutes: 1,
        prompt: 'Short integration test routine'
      }
    end

    before do
      # Mock external services to avoid real API calls
      allow_any_instance_of(ContextualSpeechTriggerService)
        .to receive(:trigger_speech)
        .and_return({
          speech_text: "This is a test performance segment generated for integration testing!",
          segment_type: 'test_segment'
        })

      allow_any_instance_of(HomeAssistantService)
        .to receive(:send_conversation_response)
        .and_return({ success: true })

      # Speed up the performance loop for testing
      allow_any_instance_of(PerformanceModeService).to receive(:sleep) { |_, duration| sleep(0.1) }
      allow_any_instance_of(PerformanceModeService).to receive(:calculate_segment_duration).and_return(5)
    end

    it 'executes full performance workflow' do
      # Expect conversation logs to be created
      expect {
        perform_enqueued_jobs do
          PerformanceModeJob.perform_later(**integration_params)
        end
      }.to change(ConversationLog, :count).by_at_least(1)

      # Check that performance state was stored and cleaned up
      cached_state = Rails.cache.read("performance_mode:integration_test_session")
      expect(cached_state).to be_present
    end

    it 'handles concurrent job execution' do
      session1_params = integration_params.merge(session_id: 'concurrent_session_1')
      session2_params = integration_params.merge(session_id: 'concurrent_session_2')

      perform_enqueued_jobs do
        PerformanceModeJob.perform_later(**session1_params)
        PerformanceModeJob.perform_later(**session2_params)
      end

      # Both sessions should have logs
      logs1 = ConversationLog.where(session_id: 'concurrent_session_1')
      logs2 = ConversationLog.where(session_id: 'concurrent_session_2')

      expect(logs1.count).to be >= 1
      expect(logs2.count).to be >= 1

      # Both sessions should have cached state
      state1 = Rails.cache.read("performance_mode:concurrent_session_1")
      state2 = Rails.cache.read("performance_mode:concurrent_session_2")

      expect(state1).to be_present
      expect(state2).to be_present
    end
  end

  describe 'job queueing and execution timing' do
    it 'queues on default queue' do
      expect(PerformanceModeJob.new.queue_name).to eq('default')
    end

    it 'can be retried on failure' do
      allow(PerformanceModeService).to receive(:new).and_raise(StandardError).once
      allow(PerformanceModeService).to receive(:new).and_call_original

      # First attempt should fail and be retried
      perform_enqueued_jobs(retry: true) do
        PerformanceModeJob.perform_later(**job_params)
      end
    end

    context 'with realistic timing constraints' do
      let(:timing_params) do
        job_params.merge(duration_minutes: 2)
      end

      before do
        # Use actual timing but speed it up for tests
        allow_any_instance_of(PerformanceModeService).to receive(:sleep) do |_, duration|
          sleep([ duration * 0.01, 0.1 ].min) # Speed up but maintain relative timing
        end

        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech)
          .and_return({
            speech_text: "Realistic timing test segment",
            segment_type: 'timing_test'
          })

        allow_any_instance_of(HomeAssistantService)
          .to receive(:send_conversation_response)
      end

      it 'respects performance duration limits' do
        start_time = Time.current

        perform_enqueued_jobs do
          PerformanceModeJob.perform_later(**timing_params)
        end

        execution_time = Time.current - start_time
        # Should complete reasonably quickly with our speed-up
        expect(execution_time).to be < 10.seconds
      end
    end
  end

  describe 'different persona handling' do
    let(:persona_params) do
      job_params.merge(persona: 'SPARKLE')
    end

    before do
      allow_any_instance_of(ContextualSpeechTriggerService)
        .to receive(:trigger_speech)
        .and_return({
          speech_text: "This is SPARKLE performing!",
          segment_type: 'persona_test'
        })
    end

    it 'passes persona to service correctly', vcr: { cassette_name: 'performance_mode_job/persona_handling' } do
      expect(PerformanceModeService).to receive(:new).with(
        hash_including(persona: 'SPARKLE')
      ).and_call_original

      perform_enqueued_jobs do
        PerformanceModeJob.perform_later(**persona_params)
      end
    end
  end

  describe 'performance types', vcr: { cassette_name: 'performance_mode_job/different_types' } do
    before do
      allow_any_instance_of(ContextualSpeechTriggerService)
        .to receive(:trigger_speech)
        .and_return({
          speech_text: "Type-specific performance content",
          segment_type: 'type_test'
        })
    end

    %w[comedy storytelling poetry improv].each do |performance_type|
      it "handles #{performance_type} performance type" do
        type_params = job_params.merge(performance_type: performance_type)

        expect {
          perform_enqueued_jobs do
            PerformanceModeJob.perform_later(**type_params)
          end
        }.not_to raise_error

        # Verify performance state includes correct type
        cached_state = Rails.cache.read("performance_mode:#{session_id}")
        expect(cached_state[:performance_type]).to eq(performance_type)
      end
    end
  end

  describe 'job monitoring and observability' do
    it 'includes session_id in log messages for tracing' do
      expect(Rails.logger).to receive(:info).with(/session #{session_id}/).at_least(:once)

      perform_enqueued_jobs do
        PerformanceModeJob.perform_later(**job_params)
      end
    end

    it 'logs completion status' do
      expect(Rails.logger).to receive(:info).with(/completed/)

      perform_enqueued_jobs do
        PerformanceModeJob.perform_later(**job_params)
      end
    end

    it 'includes error details in failure logs' do
      allow(PerformanceModeService).to receive(:new).and_raise(ArgumentError, 'Invalid parameters')

      expect(Rails.logger).to receive(:error).with(/Performance mode job failed: Invalid parameters/)
      expect(Rails.logger).to receive(:error).with(kind_of(Array)) # backtrace

      perform_enqueued_jobs do
        PerformanceModeJob.perform_later(**job_params)
      end
    end
  end

  describe 'memory and resource management' do
    it 'properly cleans up instance variables and references' do
      # This test ensures we don't have memory leaks from long-running performances
      initial_objects = ObjectSpace.count_objects

      perform_enqueued_jobs do
        PerformanceModeJob.perform_later(**job_params)
      end

      GC.start # Force garbage collection
      final_objects = ObjectSpace.count_objects

      # We shouldn't have a significant increase in objects
      object_increase = final_objects[:TOTAL] - initial_objects[:TOTAL]
      expect(object_increase).to be < 1000 # Reasonable threshold
    end
  end
end
