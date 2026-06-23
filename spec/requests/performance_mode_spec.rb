# spec/requests/performance_mode_spec.rb

require 'rails_helper'

RSpec.describe 'Performance Mode API', type: :request do
  let(:session_id) { 'api_test_session' }
  let(:headers) { { 'X-Session-ID' => session_id, 'Content-Type' => 'application/json' } }
  let(:base_performance_params) do
    {
      performance_type: 'comedy',
      duration_minutes: 2,
      prompt: 'Custom API test prompt'
    }
  end

  before do
    Rails.cache.clear
    ConversationLog.where(session_id: session_id).delete_all
    clear_enqueued_jobs
    clear_performed_jobs
    # Prevent HomeAssistant calls triggered by wake-word interruptions
    allow_any_instance_of(HomeAssistantService).to receive(:send_conversation_response).and_return(true)
    allow_any_instance_of(HomeAssistantService).to receive(:call_service).and_return(true)
  end

  after do
    Rails.cache.clear
  end

  describe 'POST /api/v1/performance_mode/start' do
    context 'with valid parameters' do
      it 'starts a new performance successfully' do
        post '/api/v1/performance_mode/start',
             params: base_performance_params.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq('Performance mode started')
        expect(json_response['session_id']).to eq(session_id)
        expect(json_response['performance_type']).to eq('comedy')
        expect(json_response['duration_minutes']).to eq(2)
        expect(json_response['estimated_end_time']).to be_present
      end

      it 'enqueues background job' do
        expect {
          post '/api/v1/performance_mode/start',
               params: base_performance_params.to_json,
               headers: headers
        }.to have_enqueued_job(PerformanceModeJob)
      end

      it 'stores performance state in cache' do
        post '/api/v1/performance_mode/start',
             params: base_performance_params.to_json,
             headers: headers

        cached_state = Rails.cache.read("performance_mode:#{session_id}")
        expect(cached_state).to be_present
        expect(cached_state[:performance_type]).to eq('comedy')
        expect(cached_state[:is_running]).to be true
      end
    end

    context 'with session_id in parameters' do
      after { PerformanceModeService.stop_active_performance('param_session_test') }

      it 'uses session_id from params over headers' do
        param_session_id = 'param_session_test'
        params_with_session = base_performance_params.merge(session_id: param_session_id)

        post '/api/v1/performance_mode/start',
             params: params_with_session.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['session_id']).to eq(param_session_id)
      end
    end

    context 'with default parameters' do
      it 'uses default values when parameters not provided' do
        post '/api/v1/performance_mode/start', headers: headers

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['performance_type']).to eq('comedy')
        expect(json_response['duration_minutes']).to eq(10)
      end
    end

    context 'with custom persona' do
      it 'passes persona parameter correctly' do
        params_with_persona = base_performance_params.merge(persona: 'SPARKLE')

        post '/api/v1/performance_mode/start',
             params: params_with_persona.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
        expect(PerformanceModeJob).to have_been_enqueued.with(
          hash_including(persona: 'SPARKLE')
        )
      end
    end

    context 'when performance already running' do
      before do
        PerformanceModeService.start_performance(
          session_id: session_id,
          performance_type: 'storytelling',
          duration_minutes: 5
        )
      end

      it 'returns error for duplicate performance' do
        post '/api/v1/performance_mode/start',
             params: base_performance_params.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('Performance already running')
        expect(json_response['current_performance']).to be_present
        expect(json_response['current_performance']['type']).to eq('storytelling')
      end
    end

    context 'when service raises exception' do
      before do
        allow(PerformanceModeService).to receive(:start_performance)
          .and_raise(StandardError, 'Service unavailable')
      end

      it 'returns error response' do
        post '/api/v1/performance_mode/start',
             params: base_performance_params.to_json,
             headers: headers

        expect(response).to have_http_status(:internal_server_error)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Failed to start performance mode')
        expect(json_response['details']).to eq('Service unavailable')
      end
    end
  end

  describe 'POST /api/v1/performance_mode/stop' do
    context 'with active performance' do
      before do
        PerformanceModeService.start_performance(**base_performance_params.merge(session_id: session_id))
      end

      it 'stops the performance successfully' do
        post '/api/v1/performance_mode/stop', headers: headers

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq('Performance mode stopped')
        expect(json_response['reason']).to eq('manual_stop')
        expect(json_response['session_id']).to eq(session_id)
      end

      it 'updates performance state' do
        post '/api/v1/performance_mode/stop', headers: headers

        service = PerformanceModeService.get_active_performance(session_id)
        expect(service.instance_variable_get(:@should_stop)).to be true
        expect(service.instance_variable_get(:@is_running)).to be false
      end

      it 'accepts custom stop reason' do
        stop_params = { reason: 'emergency_stop' }

        post '/api/v1/performance_mode/stop',
             params: stop_params.to_json,
             headers: headers

        json_response = JSON.parse(response.body)
        expect(json_response['reason']).to eq('emergency_stop')
      end
    end

    context 'with no active performance' do
      it 'returns not found response' do
        post '/api/v1/performance_mode/stop', headers: headers

        expect(response).to have_http_status(:not_found)

        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq('No active performance to stop')
      end
    end

    context 'when service raises exception' do
      before do
        PerformanceModeService.start_performance(**base_performance_params.merge(session_id: session_id))
        allow(PerformanceModeService).to receive(:stop_active_performance)
          .and_raise(StandardError, 'Stop failed')
      end

      it 'returns error response' do
        post '/api/v1/performance_mode/stop', headers: headers

        expect(response).to have_http_status(:internal_server_error)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Failed to stop performance mode')
        expect(json_response['details']).to eq('Stop failed')
      end
    end
  end

  describe 'GET /api/v1/performance_mode/status' do
    context 'with active performance' do
      before do
        freeze_time do
          PerformanceModeService.start_performance(
            session_id: session_id,
            performance_type: 'poetry',
            duration_minutes: 15
          )
        end
      end

      it 'returns active performance status' do
        freeze_time do
          get '/api/v1/performance_mode/status', headers: headers

          expect(response).to have_http_status(:ok)

          json_response = JSON.parse(response.body)
          expect(json_response['active']).to be true
          expect(json_response['session_id']).to eq(session_id)
          expect(json_response['performance_type']).to eq('poetry')
          expect(json_response['time_remaining_seconds']).to be_within(5).of(900) # 15 minutes
          expect(json_response['time_remaining_minutes']).to be_within(0.1).of(15.0)
          expect(json_response['duration_minutes']).to eq(15)
          expect(json_response['start_time']).to be_present
          expect(json_response['estimated_end_time']).to be_present
        end
      end

      it 'updates time remaining accurately' do
        travel_to(5.minutes.from_now) do
          get '/api/v1/performance_mode/status', headers: headers

          json_response = JSON.parse(response.body)
          expect(json_response['time_remaining_minutes']).to eq(10.0)
        end
      end
    end

    context 'with no active performance' do
      it 'returns inactive status' do
        get '/api/v1/performance_mode/status', headers: headers

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['active']).to be false
        expect(json_response['session_id']).to eq(session_id)
        expect(json_response['message']).to eq('No active performance')
      end
    end

    context 'when service raises exception' do
      before do
        allow(PerformanceModeService).to receive(:get_active_performance)
          .and_raise(StandardError, 'Status check failed')
      end

      it 'returns error response' do
        get '/api/v1/performance_mode/status', headers: headers

        expect(response).to have_http_status(:internal_server_error)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Failed to get performance status')
        expect(json_response['details']).to eq('Status check failed')
      end
    end
  end

  describe 'POST /api/v1/performance_mode/interrupt' do
    context 'with active performance' do
      let(:mock_service) { instance_double(PerformanceModeService) }

      before do
        allow(PerformanceModeService).to receive(:get_active_performance).and_return(mock_service)
        allow(mock_service).to receive(:is_running?).and_return(true)
        allow(mock_service).to receive(:interrupt_for_wake_word)
      end

      it 'interrupts the performance for wake word' do
        expect(mock_service).to receive(:interrupt_for_wake_word)

        post '/api/v1/performance_mode/interrupt', headers: headers

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq('Performance interrupted for wake word')
        expect(json_response['session_id']).to eq(session_id)
      end
    end

    context 'with inactive performance' do
      before do
        allow(PerformanceModeService).to receive(:get_active_performance).and_return(nil)
      end

      it 'returns not found response' do
        post '/api/v1/performance_mode/interrupt', headers: headers

        expect(response).to have_http_status(:not_found)

        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq('No active performance to interrupt')
      end
    end

    context 'with stopped performance' do
      let(:mock_service) { instance_double(PerformanceModeService) }

      before do
        allow(PerformanceModeService).to receive(:get_active_performance).and_return(mock_service)
        allow(mock_service).to receive(:is_running?).and_return(false)
      end

      it 'returns not found response for stopped performance' do
        post '/api/v1/performance_mode/interrupt', headers: headers

        expect(response).to have_http_status(:not_found)

        json_response = JSON.parse(response.body)
        expect(json_response['message']).to eq('No active performance to interrupt')
      end
    end

    context 'when service raises exception' do
      before do
        allow(PerformanceModeService).to receive(:get_active_performance)
          .and_raise(StandardError, 'Interrupt failed')
      end

      it 'returns error response' do
        post '/api/v1/performance_mode/interrupt', headers: headers

        expect(response).to have_http_status(:internal_server_error)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Failed to interrupt performance')
        expect(json_response['details']).to eq('Interrupt failed')
      end
    end
  end

  describe 'session ID handling' do
    context 'with X-Session-ID header' do
      after { PerformanceModeService.stop_active_performance('header_session_123') }

      it 'uses session ID from header' do
        header_session = 'header_session_123'
        test_headers = { 'X-Session-ID' => header_session, 'Content-Type' => 'application/json' }

        post '/api/v1/performance_mode/start',
             params: base_performance_params.to_json,
             headers: test_headers

        json_response = JSON.parse(response.body)
        expect(json_response['session_id']).to eq(header_session)
      end
    end

    context 'with session_id in params and header' do
      after { PerformanceModeService.stop_active_performance('param_session_456') }

      it 'prioritizes session_id from params' do
        param_session = 'param_session_456'
        header_session = 'header_session_789'

        params_with_session = base_performance_params.merge(session_id: param_session)
        test_headers = { 'X-Session-ID' => header_session, 'Content-Type' => 'application/json' }

        post '/api/v1/performance_mode/start',
             params: params_with_session.to_json,
             headers: test_headers

        json_response = JSON.parse(response.body)
        expect(json_response['session_id']).to eq(param_session)
      end
    end

    context 'with no session ID provided' do
      after { PerformanceModeService.stop_active_performance('default_performance_session') }

      it 'uses default session ID' do
        post '/api/v1/performance_mode/start',
             params: base_performance_params.to_json,
             headers: { 'Content-Type' => 'application/json' }

        json_response = JSON.parse(response.body)
        expect(json_response['session_id']).to eq('default_performance_session')
      end
    end
  end

  describe 'complete performance workflow' do
    it 'handles full start -> status -> interrupt -> status workflow' do
      mock_service = instance_double(PerformanceModeService)
      allow(mock_service).to receive(:is_running?).and_return(true, true, false)
      allow(mock_service).to receive(:performance_type).and_return('comedy')
      allow(mock_service).to receive(:time_remaining).and_return(120)
      allow(mock_service).to receive(:duration_minutes).and_return(2)
      allow(mock_service).to receive(:instance_variable_get).with(:@start_time).and_return(Time.current)
      allow(mock_service).to receive(:instance_variable_get).with(:@end_time).and_return(2.minutes.from_now)
      allow(mock_service).to receive(:interrupt_for_wake_word)

      # Start performance
      post '/api/v1/performance_mode/start',
           params: base_performance_params.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['message']).to eq('Performance mode started')

      # Check status - should be active (use real service from cache)
      get '/api/v1/performance_mode/status', headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['active']).to be true

      # Interrupt performance
      allow(PerformanceModeService).to receive(:get_active_performance).and_return(mock_service)

      post '/api/v1/performance_mode/interrupt', headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['message']).to include('interrupted')
    end
  end

  describe 'multiple concurrent sessions' do
    let(:session1) { 'concurrent_session_1' }
    let(:session2) { 'concurrent_session_2' }
    let(:headers1) { { 'X-Session-ID' => session1, 'Content-Type' => 'application/json' } }
    let(:headers2) { { 'X-Session-ID' => session2, 'Content-Type' => 'application/json' } }

    after do
      PerformanceModeService.stop_active_performance(session1)
      PerformanceModeService.stop_active_performance(session2)
    end

    it 'handles multiple concurrent performance sessions' do
      post '/api/v1/performance_mode/start',
           params: base_performance_params.merge(performance_type: 'comedy').to_json,
           headers: headers1
      expect(response).to have_http_status(:ok)

      post '/api/v1/performance_mode/start',
           params: base_performance_params.merge(performance_type: 'storytelling').to_json,
           headers: headers2
      expect(response).to have_http_status(:ok)

      get '/api/v1/performance_mode/status', headers: headers1
      session1_status = JSON.parse(response.body)
      expect(session1_status['active']).to be true
      expect(session1_status['performance_type']).to eq('comedy')

      get '/api/v1/performance_mode/status', headers: headers2
      session2_status = JSON.parse(response.body)
      expect(session2_status['active']).to be true
      expect(session2_status['performance_type']).to eq('storytelling')

      post '/api/v1/performance_mode/stop', headers: headers1
      expect(response).to have_http_status(:ok)

      get '/api/v1/performance_mode/status', headers: headers2
      session2_final = JSON.parse(response.body)
      expect(session2_final['active']).to be true
    end
  end

  describe 'error recovery and edge cases' do
    context 'with missing Content-Type header' do
      it 'handles requests without Content-Type' do
        post '/api/v1/performance_mode/start',
             params: base_performance_params.to_json,
             headers: { 'X-Session-ID' => session_id }

        expect(response.status).to be_between(200, 422)
      end
    end

    context 'with extremely large duration' do
      it 'handles unreasonably large duration values' do
        large_duration_params = base_performance_params.merge(duration_minutes: 99999)

        post '/api/v1/performance_mode/start',
             params: large_duration_params.to_json,
             headers: headers

        expect(response.status).to be_between(200, 422)
      end
    end

    context 'with invalid performance type' do
      it 'handles unknown performance types' do
        invalid_type_params = base_performance_params.merge(performance_type: 'invalid_type')

        post '/api/v1/performance_mode/start',
             params: invalid_type_params.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['performance_type']).to eq('invalid_type')
      end
    end
  end

  describe 'logging and observability' do
    it 'logs performance start requests' do
      allow(Rails.logger).to receive(:info)
      expect(Rails.logger).to receive(:info).with(/Starting .* performance for .* minutes/).at_least(:once)

      post '/api/v1/performance_mode/start',
           params: base_performance_params.to_json,
           headers: headers
    end

    it 'logs errors with sufficient detail' do
      allow(PerformanceModeService).to receive(:start_performance)
        .and_raise(StandardError, 'Test error for logging')

      allow(Rails.logger).to receive(:error)
      expect(Rails.logger).to receive(:error).with(/Failed to start performance mode: Test error for logging/).at_least(:once)

      post '/api/v1/performance_mode/start',
           params: base_performance_params.to_json,
           headers: headers
    end
  end
end
