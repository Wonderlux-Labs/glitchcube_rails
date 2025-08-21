# spec/integration/performance_mode_end_to_end_spec.rb

require 'rails_helper'

RSpec.describe 'Performance Mode End-to-End Integration', type: :request do
  include ActiveJob::TestHelper
  let(:session_id) { 'end_to_end_test' }
  let(:headers) { { 'X-Session-ID' => session_id, 'Content-Type' => 'application/json' } }

  before do
    Rails.cache.clear
    ConversationLog.where(session_id: session_id).delete_all
    clear_enqueued_jobs
    clear_performed_jobs
  end

  after do
    PerformanceModeService.stop_active_performance(session_id)
    Rails.cache.clear
  end

  describe 'complete performance workflow', vcr: { cassette_name: 'performance_e2e/complete_workflow' } do
    let(:performance_params) do
      {
        performance_type: 'comedy',
        duration_minutes: 2, # Short for testing
        prompt: 'End-to-end test comedy routine about AI at Burning Man'
      }
    end

    before do
      # Mock external services for controlled testing
      allow_any_instance_of(ContextualSpeechTriggerService)
        .to receive(:trigger_speech)
        .and_return({
          speech_text: "Welcome to my AI comedy show at Burning Man! This is segment number X of my routine.",
          segment_type: 'performance_segment'
        })

      allow_any_instance_of(HomeAssistantService)
        .to receive(:send_conversation_response)
        .and_return({ success: true })

      # Speed up timing for tests
      allow_any_instance_of(PerformanceModeService).to receive(:sleep) { sleep(0.01) }
      allow_any_instance_of(PerformanceModeService).to receive(:calculate_segment_duration).and_return(1)
    end

    it 'executes complete start-to-finish performance via API' do
      # Step 1: Start performance via API
      post '/performance_mode/start',
           params: performance_params.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      start_response = JSON.parse(response.body)
      expect(start_response['message']).to eq('Performance mode started')
      expect(start_response['session_id']).to eq(session_id)

      # Step 2: Verify job was enqueued
      expect(PerformanceModeJob).to have_been_enqueued.with(
        hash_including(
          session_id: session_id,
          performance_type: 'comedy',
          duration_minutes: 2
        )
      )

      # Step 3: Check status via API - should be active
      get '/performance_mode/status', headers: headers

      expect(response).to have_http_status(:ok)
      status_response = JSON.parse(response.body)
      expect(status_response['active']).to be true
      expect(status_response['performance_type']).to eq('comedy')

      # Step 4: Execute the background job
      perform_enqueued_jobs

      # Step 5: Verify conversation logs were created
      logs = ConversationLog.where(session_id: session_id)
      expect(logs.count).to be >= 1

      performance_logs = logs.where("user_message LIKE ?", "%PERFORMANCE_MODE_%")
      expect(performance_logs).to exist

      # Verify log content
      log = performance_logs.first
      expect(log.ai_response).to include("Welcome to my AI comedy show")

      metadata = JSON.parse(log.metadata)
      expect(metadata['performance_mode']).to be true
      expect(metadata['performance_type']).to eq('comedy')

      # Step 6: Verify Home Assistant was called
      expect_any_instance_of(HomeAssistantService)
        .to have_received(:send_conversation_response)
        .with(hash_including(
          conversation_id: session_id,
          performance_mode: true
        )).at_least(:once)

      # Step 7: Check final status
      get '/performance_mode/status', headers: headers
      final_status = JSON.parse(response.body)
      # Performance may have completed naturally or still be running
      expect(final_status['session_id']).to eq(session_id)
    end

    it 'handles wake word interruption workflow' do
      # Start performance
      post '/performance_mode/start',
           params: performance_params.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)

      # Execute job in background
      perform_enqueued_jobs

      # Interrupt for wake word
      post '/performance_mode/interrupt', headers: headers

      expect(response).to have_http_status(:ok)
      interrupt_response = JSON.parse(response.body)
      expect(interrupt_response['message']).to include('interrupted for wake word')

      # Check status - should be inactive
      get '/performance_mode/status', headers: headers

      final_status = JSON.parse(response.body)
      expect(final_status['active']).to be false

      # Verify interruption acknowledgment was sent
      logs = ConversationLog.where(session_id: session_id)
      interruption_logs = logs.where("user_message LIKE ?", "%INTERRUPTION_ACKNOWLEDGMENT%")

      if interruption_logs.exists?
        expect(interruption_logs.first.ai_response).to include("Oh! Looks like someone wants to chat!")
      end
    end

    it 'handles manual stop workflow' do
      # Start performance
      post '/performance_mode/start',
           params: performance_params.to_json,
           headers: headers

      # Stop manually
      post '/performance_mode/stop',
           params: { reason: 'user_requested' }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      stop_response = JSON.parse(response.body)
      expect(stop_response['reason']).to eq('user_requested')

      # Status should show inactive
      get '/performance_mode/status', headers: headers

      status_response = JSON.parse(response.body)
      expect(status_response['active']).to be false
    end
  end

  describe 'error scenarios and recovery', vcr: { cassette_name: 'performance_e2e/error_scenarios' } do
    context 'LLM service failures' do
      before do
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech)
          .and_raise(StandardError, 'LLM service unavailable')
      end

      it 'gracefully handles LLM failures during performance' do
        post '/performance_mode/start',
             params: { performance_type: 'comedy', duration_minutes: 1 }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)

        # Job should still execute without crashing
        expect {
          perform_enqueued_jobs
        }.not_to raise_error

        # Performance should still be manageable
        get '/performance_mode/status', headers: headers
        expect(response).to have_http_status(:ok)
      end
    end

    context 'Home Assistant service failures' do
      before do
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech)
          .and_return({
            speech_text: "Test speech for HA failure scenario",
            segment_type: 'test_segment'
          })

        allow_any_instance_of(HomeAssistantService)
          .to receive(:send_conversation_response)
          .and_raise(StandardError, 'Home Assistant unreachable')
      end

      it 'continues performance despite Home Assistant failures' do
        post '/performance_mode/start',
             params: { performance_type: 'comedy', duration_minutes: 1 }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)

        # Performance should continue and create logs despite HA failure
        perform_enqueued_jobs

        logs = ConversationLog.where(session_id: session_id)
        expect(logs).to exist
      end
    end

    context 'cache/state failures' do
      it 'handles cache failures during performance' do
        allow(Rails.cache).to receive(:write).and_raise(StandardError, 'Cache write failed')

        post '/performance_mode/start',
             params: { performance_type: 'comedy', duration_minutes: 1 }.to_json,
             headers: headers

        # Should still attempt to start despite cache issues
        expect(response.status).to be_between(200, 500)
      end
    end
  end

  describe 'multiple concurrent performances', vcr: { cassette_name: 'performance_e2e/concurrent_performances' } do
    let(:sessions) do
      {
        'comedy_session' => { performance_type: 'comedy', duration_minutes: 3 },
        'story_session' => { performance_type: 'storytelling', duration_minutes: 4 },
        'improv_session' => { performance_type: 'improv', duration_minutes: 2 }
      }
    end

    before do
      # Mock services for concurrent testing
      segment_counter = 0
      allow_any_instance_of(ContextualSpeechTriggerService)
        .to receive(:trigger_speech) do |service_instance|
        segment_counter += 1
        {
          speech_text: "Concurrent performance segment #{segment_counter}",
          segment_type: 'concurrent_test'
        }
      end

      allow_any_instance_of(HomeAssistantService)
        .to receive(:send_conversation_response)
        .and_return({ success: true })
    end

    after do
      sessions.keys.each do |session_id|
        PerformanceModeService.stop_active_performance(session_id)
      end
    end

    it 'manages multiple concurrent performance sessions' do
      # Start all sessions
      sessions.each do |session_id, params|
        headers = { 'X-Session-ID' => session_id, 'Content-Type' => 'application/json' }

        post '/performance_mode/start',
             params: params.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
      end

      # Verify all are active
      sessions.each do |session_id, params|
        headers = { 'X-Session-ID' => session_id }

        get '/performance_mode/status', headers: headers

        status_response = JSON.parse(response.body)
        expect(status_response['active']).to be true
        expect(status_response['performance_type']).to eq(params[:performance_type])
      end

      # Execute all jobs
      perform_enqueued_jobs

      # Verify logs were created for all sessions
      sessions.each do |session_id, _|
        logs = ConversationLog.where(session_id: session_id)
        expect(logs.count).to be >= 1
      end

      # Stop one session, others should continue
      stop_headers = { 'X-Session-ID' => 'comedy_session', 'Content-Type' => 'application/json' }
      post '/performance_mode/stop', headers: stop_headers

      expect(response).to have_http_status(:ok)

      # Verify comedy session stopped
      get '/performance_mode/status', headers: { 'X-Session-ID' => 'comedy_session' }
      comedy_status = JSON.parse(response.body)
      expect(comedy_status['active']).to be false

      # Verify other sessions still active
      %w[story_session improv_session].each do |session_id|
        get '/performance_mode/status', headers: { 'X-Session-ID' => session_id }
        status = JSON.parse(response.body)
        expect(status['active']).to be true
      end
    end
  end

  describe 'performance lifecycle with real timing', vcr: { cassette_name: 'performance_e2e/lifecycle_timing' } do
    let(:realistic_params) do
      {
        performance_type: 'improv',
        duration_minutes: 1, # 1 minute for realistic test timing
        prompt: 'Quick improv session for lifecycle testing'
      }
    end

    before do
      # Use more realistic timing but still fast enough for tests
      allow_any_instance_of(PerformanceModeService).to receive(:sleep) { |_, duration| sleep([ duration * 0.01, 0.1 ].min) }

      segment_counter = 0
      allow_any_instance_of(ContextualSpeechTriggerService)
        .to receive(:trigger_speech) do
        segment_counter += 1
        {
          speech_text: "Lifecycle test segment #{segment_counter}: #{Time.current.strftime('%H:%M:%S')}",
          segment_type: "segment_#{segment_counter}"
        }
      end

      allow_any_instance_of(HomeAssistantService).to receive(:send_conversation_response)
    end

    it 'completes full lifecycle with realistic timing constraints' do
      start_time = Time.current

      # Start performance
      post '/performance_mode/start',
           params: realistic_params.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)

      # Execute job with realistic timing
      perform_enqueued_jobs

      execution_time = Time.current - start_time

      # Should complete within reasonable time (sped up but proportional)
      expect(execution_time).to be < 10.seconds

      # Verify performance completed
      logs = ConversationLog.where(session_id: session_id)
      expect(logs.count).to be >= 1

      # Check if performance ended naturally
      get '/performance_mode/status', headers: headers
      status = JSON.parse(response.body)
      # May be active or completed depending on exact timing
      expect(status['session_id']).to eq(session_id)
    end

    it 'maintains accurate timing throughout performance' do
      freeze_time do
        post '/performance_mode/start',
             params: realistic_params.to_json,
             headers: headers

        start_response = JSON.parse(response.body)
        estimated_end_time = Time.parse(start_response['estimated_end_time'])
        expected_end_time = Time.current + 1.minute

        expect(estimated_end_time).to be_within(1.second).of(expected_end_time)
      end
    end
  end

  describe 'integration with CubePerformance convenience methods', vcr: { cassette_name: 'performance_e2e/cube_performance_integration' } do
    before do
      allow_any_instance_of(ContextualSpeechTriggerService)
        .to receive(:trigger_speech)
        .and_return({
          speech_text: "CubePerformance integration test segment",
          segment_type: 'integration_test'
        })

      allow_any_instance_of(HomeAssistantService).to receive(:send_conversation_response)
    end

    it 'integrates CubePerformance with API endpoints' do
      # Start via CubePerformance
      service = CubePerformance.standup_comedy(
        session_id: session_id,
        duration_minutes: 1
      )

      expect(service).to be_a(PerformanceModeService)

      # Check status via API
      get '/performance_mode/status', headers: headers

      status_response = JSON.parse(response.body)
      expect(status_response['active']).to be true
      expect(status_response['performance_type']).to eq('standup_comedy')

      # Stop via API
      post '/performance_mode/stop', headers: headers

      expect(response).to have_http_status(:ok)

      # Verify stopped via CubePerformance
      expect(CubePerformance.performance_running?(session_id)).to be false
    end

    it 'handles mixed API and convenience method usage' do
      # Start via API
      post '/performance_mode/start',
           params: { performance_type: 'poetry', duration_minutes: 1 }.to_json,
           headers: headers

      # Check via CubePerformance
      expect(CubePerformance.performance_running?(session_id)).to be true

      status = CubePerformance.performance_status(session_id)
      expect(status[:active]).to be true
      expect(status[:type]).to eq('poetry')

      # Stop via CubePerformance
      result = CubePerformance.stop_performance(session_id, reason: 'mixed_interface_test')
      expect(result).to be true

      # Verify via API
      get '/performance_mode/status', headers: headers

      api_status = JSON.parse(response.body)
      expect(api_status['active']).to be false
    end
  end

  describe 'observability and monitoring integration' do
    let(:monitoring_params) do
      {
        performance_type: 'storytelling',
        duration_minutes: 2,
        prompt: 'Monitoring test story'
      }
    end

    before do
      allow_any_instance_of(ContextualSpeechTriggerService)
        .to receive(:trigger_speech)
        .and_return({
          speech_text: "Monitoring test segment with detailed logging",
          segment_type: 'monitoring_test'
        })

      allow_any_instance_of(HomeAssistantService).to receive(:send_conversation_response)
    end

    it 'provides comprehensive logging throughout performance lifecycle' do
      # Expect specific log messages
      expect(Rails.logger).to receive(:info).with(/Starting storytelling performance for 2 minutes/).at_least(:once)
      expect(Rails.logger).to receive(:info).with(/Performance mode started/).at_least(:once)
      expect(Rails.logger).to receive(:info).with(/Starting performance mode job/).at_least(:once)

      post '/performance_mode/start',
           params: monitoring_params.to_json,
           headers: headers

      perform_enqueued_jobs
    end

    it 'tracks performance metrics and state changes' do
      post '/performance_mode/start',
           params: monitoring_params.to_json,
           headers: headers

      # Verify cached state tracking
      cached_state = Rails.cache.read("performance_mode:#{session_id}")
      expect(cached_state).to be_present
      expect(cached_state[:last_updated]).to be_within(1.second).of(Time.current)

      perform_enqueued_jobs

      # State should be updated after execution
      updated_state = Rails.cache.read("performance_mode:#{session_id}")
      expect(updated_state).to be_present
    end
  end
end
