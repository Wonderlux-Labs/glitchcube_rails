# spec/integration/performance_mode_end_to_end_spec.rb

require 'rails_helper'
require 'benchmark'

# Fast end-to-end smoke of the performance lifecycle, driven by a virtual clock.
#
# Why this is fast: PerformanceModeService.clock is swapped for a single shared
# FakeClock. The brain (ContextualSpeechTriggerService) is canned and Home
# Assistant is the in-memory FakeHomeAssistant, so nothing touches the network.
# The performance loop's inter-segment "sleeps" advance virtual time instead of
# blocking, so the whole duration is consumed in microseconds and the loop exits
# the instant virtual `now` reaches `@end_time`. The whole file runs in well
# under a second of wall-clock time.
#
# We assert on OBSERVABLE behavior — segments spoken to HA, conversation logs,
# API status — not on internal mocks.
RSpec.describe 'Performance Mode end-to-end (virtual clock)', type: :request do
  include ActiveJob::TestHelper

  let(:session_id) { 'e2e_perf_session' }
  let(:headers) { { 'X-Session-ID' => session_id, 'Content-Type' => 'application/json' } }
  let(:clock) { FakeClock.new }
  let(:fake_ha) { FakeHomeAssistant.new(persona: 'buddy') }

  let(:segment_speech) { 'Welcome to the AI comedy hour at Burning Man!' }

  before do
    Rails.cache.clear
    ConversationLog.where(session_id: session_id).delete_all
    clear_enqueued_jobs
    clear_performed_jobs

    # One shared virtual clock for every service the lifecycle builds (controller,
    # job, reconstructed-from-cache). Sleeps advance it; the loop exits when it
    # passes @end_time.
    PerformanceModeService.clock = clock

    # In-memory Home Assistant: records every spoken segment, no real device/HTTP.
    HomeAssistantService.instance = fake_ha

    # Canned brain — deterministic segment text, no LLM/network.
    allow_any_instance_of(ContextualSpeechTriggerService)
      .to receive(:trigger_speech)
      .and_return(speech_text: segment_speech, segment_type: 'performance_segment')

    # Keep per-segment virtual gap small so a 1-minute performance yields several
    # segments before the clock runs out (60s / 5s gap ≈ 12 segments).
    allow_any_instance_of(PerformanceModeService)
      .to receive(:calculate_segment_duration).and_return(5)

    # The parent Conversation must exist (ConversationLog belongs_to :conversation).
    Conversation.find_or_create_by!(session_id: session_id) { |c| c.started_at = Time.current }
  end

  after do
    PerformanceModeService.reset_clock!
    HomeAssistantService.reset_instance!
    Rails.cache.clear
  end

  def start_performance(duration_minutes: 1)
    post '/api/v1/performance_mode/start',
         params: { performance_type: 'comedy', duration_minutes: duration_minutes,
                   prompt: 'E2E comedy routine' }.to_json,
         headers: headers
  end

  describe 'full start -> loop -> natural completion' do
    it 'starts via the API, enqueues the job, and reports active' do
      start_performance

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['message']).to eq('Performance mode started')
      expect(body['session_id']).to eq(session_id)

      expect(PerformanceModeJob).to have_been_enqueued.with(
        hash_including(session_id: session_id, performance_type: 'comedy', duration_minutes: 1)
      )

      get '/api/v1/performance_mode/status', headers: headers
      expect(JSON.parse(response.body)['active']).to be true
    end

    it 'runs the loop to produce multiple segments then exits when time expires' do
      start_performance

      # Drive the background job — the loop spins on the virtual clock and exits
      # the moment `now` passes `@end_time`. No real waiting.
      perform_enqueued_jobs

      # Multiple performance segments were spoken to Home Assistant.
      spoken_segments = fake_ha.conversation_requests.select { |r| r[:text] == segment_speech }
      expect(spoken_segments.size).to be > 1

      # ...and the segments were persisted as performance conversation logs.
      logs = ConversationLog.where(session_id: session_id)
                            .where("user_message LIKE ?", "%PERFORMANCE_MODE_PERFORMANCE_SEGMENT%")
      expect(logs.count).to be > 1
      expect(logs.first.ai_response).to eq(segment_speech)
      expect(JSON.parse(logs.first.metadata)['performance_mode']).to be true

      # Loop terminated because the virtual clock reached the planned end time, so
      # the performance no longer reports as running.
      state = Rails.cache.read("performance_mode:#{session_id}")
      expect(clock.now).to be >= state[:end_time]

      get '/api/v1/performance_mode/status', headers: headers
      expect(JSON.parse(response.body)['active']).to be false
    end

    it 'finishes in negligible wall-clock time (no real sleeping)' do
      start_performance

      wall_clock = Benchmark.realtime { perform_enqueued_jobs }
      expect(wall_clock).to be < 1.0
    end
  end

  describe 'wake-word interruption mid-lifecycle' do
    it 'stops the performance and speaks an interruption acknowledgment' do
      start_performance

      post '/api/v1/performance_mode/interrupt', headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['message']).to eq('Performance interrupted for wake word')

      get '/api/v1/performance_mode/status', headers: headers
      expect(JSON.parse(response.body)['active']).to be false

      # The interruption acknowledgment was spoken to Home Assistant.
      ack = fake_ha.conversation_requests.last
      expect(ack[:text]).to match(/someone wants to chat/i)
    end
  end

  describe 'manual stop' do
    it 'stops an active performance via the API' do
      start_performance

      post '/api/v1/performance_mode/stop',
           params: { reason: 'user_requested' }.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['reason']).to eq('user_requested')

      get '/api/v1/performance_mode/status', headers: headers
      expect(JSON.parse(response.body)['active']).to be false
    end

    it 'returns 404 when stopping with no active performance' do
      post '/api/v1/performance_mode/stop', headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
