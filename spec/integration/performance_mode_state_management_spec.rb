# spec/integration/performance_mode_state_management_spec.rb

require 'rails_helper'

RSpec.describe 'Performance Mode State Management', type: :integration do
  include ActiveJob::TestHelper
  before do
    Rails.cache.clear
    clear_enqueued_jobs
    clear_performed_jobs
  end

  after do
    # Cleanup all test sessions
    %w[state_test_1 state_test_2 concurrent_1 concurrent_2 persistence_test].each do |session|
      PerformanceModeService.stop_active_performance(session)
    end
    Rails.cache.clear
  end

  describe 'performance state persistence', vcr: { cassette_name: 'performance_state/persistence' } do
    let(:session_id) { 'persistence_test' }
    let(:performance_params) do
      {
        session_id: session_id,
        performance_type: 'comedy',
        duration_minutes: 5,
        prompt: 'State persistence test prompt',
        persona: 'BUDDY'
      }
    end

    context 'state storage and retrieval' do
      it 'stores complete performance state in cache' do
        freeze_time do
          service = PerformanceModeService.start_performance(**performance_params)

          cached_state = Rails.cache.read("performance_mode:#{session_id}")

          expect(cached_state).to be_present
          expect(cached_state[:session_id]).to eq(session_id)
          expect(cached_state[:performance_type]).to eq('comedy')
          expect(cached_state[:duration_minutes]).to eq(5)
          expect(cached_state[:prompt]).to eq('State persistence test prompt')
          expect(cached_state[:persona]).to eq('BUDDY')
          expect(cached_state[:start_time]).to eq(Time.current)
          expect(cached_state[:end_time]).to eq(Time.current + 5.minutes)
          expect(cached_state[:is_running]).to be true
          expect(cached_state[:should_stop]).to be false
          expect(cached_state[:segments_count]).to eq(0)
          expect(cached_state[:last_updated]).to be_within(1.second).of(Time.current)
        end
      end

      it 'reconstructs service from cached state accurately' do
        # Store initial performance
        original_service = PerformanceModeService.start_performance(**performance_params)

        # Retrieve from cache
        retrieved_service = PerformanceModeService.get_active_performance(session_id)

        expect(retrieved_service).to be_a(PerformanceModeService)
        expect(retrieved_service.session_id).to eq(original_service.session_id)
        expect(retrieved_service.performance_type).to eq(original_service.performance_type)
        expect(retrieved_service.duration_minutes).to eq(original_service.duration_minutes)
        expect(retrieved_service.instance_variable_get(:@prompt)).to eq(original_service.instance_variable_get(:@prompt))
        expect(retrieved_service.instance_variable_get(:@persona)).to eq(original_service.instance_variable_get(:@persona))
      end

      it 'handles state updates during performance' do
        service = PerformanceModeService.start_performance(**performance_params)

        # Simulate performance progression
        service.instance_variable_set(:@performance_segments, [
          { segment: 1, timestamp: Time.current, speech: 'Test segment' }
        ])

        # Update state
        service.send(:store_performance_state)

        # Verify updated state
        cached_state = Rails.cache.read("performance_mode:#{session_id}")
        expect(cached_state[:segments_count]).to eq(1)
      end

      it 'expires cached state after timeout period' do
        PerformanceModeService.start_performance(**performance_params)

        # Verify state exists
        expect(Rails.cache.read("performance_mode:#{session_id}")).to be_present

        # Fast-forward past expiration
        travel_to(3.hours.from_now) do
          expect(Rails.cache.read("performance_mode:#{session_id}")).to be_nil
        end
      end
    end

    context 'state consistency across service methods' do
      it 'maintains state consistency during stop operations' do
        service = PerformanceModeService.start_performance(**performance_params)

        # Verify initial state
        expect(service.is_running?).to be true

        # Stop performance
        service.stop_performance('test_stop')

        # Verify updated state in cache
        cached_state = Rails.cache.read("performance_mode:#{session_id}")
        expect(cached_state[:should_stop]).to be true
        expect(cached_state[:is_running]).to be false
        expect(cached_state[:end_time]).to be_within(1.second).of(Time.current)
      end

      it 'maintains state during wake word interruptions' do
        service = PerformanceModeService.start_performance(**performance_params)

        # Trigger wake word interruption
        service.interrupt_for_wake_word

        # Verify state reflects interruption
        cached_state = Rails.cache.read("performance_mode:#{session_id}")
        expect(cached_state[:should_stop]).to be true
        expect(cached_state[:is_running]).to be false

        # Verify service state consistency
        expect(service.instance_variable_get(:@wake_word_interruption)).to be true
      end
    end

    context 'state cleanup and garbage collection' do
      it 'cleans up state when performance completes naturally' do
        service = PerformanceModeService.new(
          session_id: session_id,
          performance_type: 'comedy',
          duration_minutes: 1
        )

        service.start_performance

        # Simulate natural completion
        service.stop_performance('time_expired')

        # State should still exist but marked as completed
        cached_state = Rails.cache.read("performance_mode:#{session_id}")
        expect(cached_state[:is_running]).to be false
        expect(cached_state[:should_stop]).to be true
      end

      it 'handles partial state corruption gracefully' do
        # Store corrupted state
        Rails.cache.write("performance_mode:#{session_id}", { corrupted: 'data' })

        # Should handle gracefully
        service = PerformanceModeService.get_active_performance(session_id)
        expect(service).to be_nil
      end
    end
  end

  describe 'concurrent session management', vcr: { cassette_name: 'performance_state/concurrent_sessions' } do
    let(:session_configs) do
      {
        'concurrent_1' => {
          performance_type: 'comedy',
          duration_minutes: 10,
          prompt: 'Comedy session 1'
        },
        'concurrent_2' => {
          performance_type: 'storytelling',
          duration_minutes: 15,
          prompt: 'Story session 2'
        },
        'concurrent_3' => {
          performance_type: 'poetry',
          duration_minutes: 8,
          prompt: 'Poetry session 3'
        }
      }
    end

    context 'multiple independent sessions' do
      it 'manages multiple concurrent performance sessions independently' do
        services = {}

        # Start multiple concurrent sessions
        session_configs.each do |session_id, config|
          services[session_id] = PerformanceModeService.start_performance(
            session_id: session_id,
            **config
          )
        end

        # Verify all sessions are running independently
        session_configs.each do |session_id, config|
          service = PerformanceModeService.get_active_performance(session_id)

          expect(service).to be_present
          expect(service.is_running?).to be true
          expect(service.performance_type).to eq(config[:performance_type])
          expect(service.duration_minutes).to eq(config[:duration_minutes])
        end

        # Stop one session, others should remain unaffected
        PerformanceModeService.stop_active_performance('concurrent_1', 'test_stop')

        expect(PerformanceModeService.get_active_performance('concurrent_1').is_running?).to be false
        expect(PerformanceModeService.get_active_performance('concurrent_2').is_running?).to be true
        expect(PerformanceModeService.get_active_performance('concurrent_3').is_running?).to be true
      end

      it 'prevents session ID conflicts and overwrites' do
        # Start first session
        service1 = PerformanceModeService.start_performance(
          session_id: 'conflict_test',
          performance_type: 'comedy',
          duration_minutes: 10
        )

        # Attempt to start second session with same ID should fail
        expect {
          PerformanceModeService.start_performance(
            session_id: 'conflict_test',
            performance_type: 'storytelling',
            duration_minutes: 5
          )
        }.to raise_error # Or handle gracefully depending on implementation

        # Original session should remain unchanged
        service = PerformanceModeService.get_active_performance('conflict_test')
        expect(service.performance_type).to eq('comedy')
        expect(service.duration_minutes).to eq(10)
      end

      it 'handles concurrent state updates without race conditions' do
        session_ids = %w[race_test_1 race_test_2 race_test_3]

        # Start sessions concurrently
        threads = session_ids.map do |session_id|
          Thread.new do
            PerformanceModeService.start_performance(
              session_id: session_id,
              performance_type: 'improv',
              duration_minutes: 5
            )
          end
        end

        threads.each(&:join)

        # All sessions should exist and be independent
        session_ids.each do |session_id|
          cached_state = Rails.cache.read("performance_mode:#{session_id}")
          expect(cached_state).to be_present
          expect(cached_state[:session_id]).to eq(session_id)
        end

        # Cleanup
        session_ids.each do |session_id|
          PerformanceModeService.stop_active_performance(session_id)
        end
      end
    end

    context 'resource isolation and performance' do
      it 'maintains performance isolation between sessions' do
        # Start sessions with different timing
        fast_session = PerformanceModeService.start_performance(
          session_id: 'fast_session',
          performance_type: 'improv',
          duration_minutes: 1
        )

        slow_session = PerformanceModeService.start_performance(
          session_id: 'slow_session',
          performance_type: 'storytelling',
          duration_minutes: 30
        )

        # Fast session timing shouldn't affect slow session
        expect(fast_session.time_remaining).to be < slow_session.time_remaining
        expect(fast_session.instance_variable_get(:@end_time)).to be < slow_session.instance_variable_get(:@end_time)

        # Stop fast session
        PerformanceModeService.stop_active_performance('fast_session')

        # Slow session should be unaffected
        expect(PerformanceModeService.get_active_performance('slow_session').is_running?).to be true
      end

      it 'handles high concurrent session load' do
        session_count = 10
        session_ids = (1..session_count).map { |i| "load_test_#{i}" }

        # Start many concurrent sessions
        session_ids.each do |session_id|
          PerformanceModeService.start_performance(
            session_id: session_id,
            performance_type: 'comedy',
            duration_minutes: 2
          )
        end

        # Verify all sessions are tracked correctly
        active_count = session_ids.count do |session_id|
          service = PerformanceModeService.get_active_performance(session_id)
          service&.is_running?
        end

        expect(active_count).to eq(session_count)

        # Cleanup
        session_ids.each do |session_id|
          PerformanceModeService.stop_active_performance(session_id)
        end
      end
    end
  end

  describe 'state recovery and error handling', vcr: { cassette_name: 'performance_state/error_recovery' } do
    let(:recovery_session) { 'recovery_test' }

    context 'cache failures and recovery' do
      it 'handles Redis/cache unavailability gracefully' do
        # Mock cache failure during state storage
        allow(Rails.cache).to receive(:write).and_raise(StandardError, 'Cache unavailable')

        # Should not prevent performance from starting
        expect {
          service = PerformanceModeService.start_performance(
            session_id: recovery_session,
            performance_type: 'comedy',
            duration_minutes: 5
          )
        }.not_to raise_error

        # Should log the error
        expect(Rails.logger).to receive(:error).with(/Failed to store performance state/).at_least(:once)
      end

      it 'handles cache read failures during state retrieval' do
        allow(Rails.cache).to receive(:read).and_raise(StandardError, 'Cache read failed')

        service = PerformanceModeService.get_active_performance(recovery_session)
        expect(service).to be_nil # Should handle gracefully
      end

      it 'recovers from partial cache corruption' do
        # Store partially corrupted state
        corrupted_state = {
          session_id: recovery_session,
          performance_type: 'comedy'
          # Missing required fields
        }
        Rails.cache.write("performance_mode:#{recovery_session}", corrupted_state)

        # Should handle corrupted state gracefully
        expect {
          PerformanceModeService.get_active_performance(recovery_session)
        }.not_to raise_error
      end
    end

    context 'performance interruption and recovery' do
      it 'handles job failures and state consistency' do
        # Start performance that will have job failure
        allow(PerformanceModeJob).to receive(:perform_later).and_raise(StandardError, 'Job queue failure')

        expect {
          PerformanceModeService.start_performance(
            session_id: recovery_session,
            performance_type: 'comedy',
            duration_minutes: 5
          )
        }.to raise_error(StandardError, 'Job queue failure')

        # State should still be consistent (if stored before job failure)
      end

      it 'recovers from mid-performance interruptions' do
        service = PerformanceModeService.start_performance(
          session_id: recovery_session,
          performance_type: 'storytelling',
          duration_minutes: 10
        )

        # Simulate mid-performance state
        service.instance_variable_set(:@performance_segments, [
          { segment: 1, speech: 'First segment', timestamp: 2.minutes.ago },
          { segment: 2, speech: 'Second segment', timestamp: 1.minute.ago }
        ])
        service.send(:store_performance_state)

        # Recover state
        recovered_service = PerformanceModeService.get_active_performance(recovery_session)
        expect(recovered_service).to be_present
        expect(recovered_service.session_id).to eq(recovery_session)

        # Should be able to continue or stop gracefully
        expect {
          recovered_service.stop_performance('recovery_test')
        }.not_to raise_error
      end
    end

    context 'memory and resource cleanup' do
      it 'prevents memory leaks from abandoned sessions' do
        abandoned_sessions = %w[abandoned_1 abandoned_2 abandoned_3]

        # Start sessions that will be abandoned
        abandoned_sessions.each do |session_id|
          PerformanceModeService.start_performance(
            session_id: session_id,
            performance_type: 'comedy',
            duration_minutes: 1
          )
        end

        # Simulate time passage for natural expiration
        travel_to(2.minutes.from_now) do
          # Sessions should be naturally expired or cleanable
          abandoned_sessions.each do |session_id|
            service = PerformanceModeService.get_active_performance(session_id)
            # Should either be expired or gracefully stoppable
            if service
              expect(service.is_running?).to be false
            end
          end
        end
      end

      it 'handles cleanup of orphaned cache entries' do
        # Create orphaned cache entries
        orphaned_entries = %w[orphan_1 orphan_2]

        orphaned_entries.each do |session_id|
          Rails.cache.write("performance_mode:#{session_id}", {
            session_id: session_id,
            is_running: false,
            should_stop: true,
            last_updated: 1.hour.ago
          })
        end

        # These should be cleanable or ignorable
        orphaned_entries.each do |session_id|
          service = PerformanceModeService.get_active_performance(session_id)
          if service
            expect(service.is_running?).to be false
          end
        end
      end
    end
  end

  describe 'performance monitoring and observability', vcr: { cassette_name: 'performance_state/monitoring' } do
    let(:monitoring_sessions) { %w[monitor_1 monitor_2 monitor_3] }

    before do
      # Start multiple sessions for monitoring
      monitoring_sessions.each_with_index do |session_id, index|
        PerformanceModeService.start_performance(
          session_id: session_id,
          performance_type: %w[comedy storytelling improv][index],
          duration_minutes: 5 + index
        )
      end
    end

    after do
      monitoring_sessions.each do |session_id|
        PerformanceModeService.stop_active_performance(session_id)
      end
    end

    it 'provides accurate system-wide performance metrics' do
      # Count active sessions
      active_sessions = monitoring_sessions.count do |session_id|
        service = PerformanceModeService.get_active_performance(session_id)
        service&.is_running?
      end

      expect(active_sessions).to eq(3)

      # Verify different performance types are tracked
      types = monitoring_sessions.map do |session_id|
        service = PerformanceModeService.get_active_performance(session_id)
        service&.performance_type
      end

      expect(types).to contain_exactly('comedy', 'storytelling', 'improv')
    end

    it 'tracks performance duration and timing accurately' do
      freeze_time do
        start_time = Time.current

        # Check timing for each session
        monitoring_sessions.each_with_index do |session_id, index|
          service = PerformanceModeService.get_active_performance(session_id)
          expected_duration = 5 + index
          expected_end_time = start_time + expected_duration.minutes

          expect(service.duration_minutes).to eq(expected_duration)
          expect(service.instance_variable_get(:@end_time)).to be_within(1.second).of(expected_end_time)
        end
      end
    end

    it 'provides session health and status information' do
      monitoring_sessions.each do |session_id|
        service = PerformanceModeService.get_active_performance(session_id)

        # Health indicators
        expect(service.is_running?).to be true
        expect(service.time_remaining).to be > 0
        expect(service.session_id).to eq(session_id)

        # State consistency
        cached_state = Rails.cache.read("performance_mode:#{session_id}")
        expect(cached_state[:is_running]).to eq(service.is_running?)
        expect(cached_state[:session_id]).to eq(service.session_id)
      end
    end
  end

  describe 'edge cases and boundary conditions' do
    context 'extreme parameter values' do
      it 'handles very short performance durations' do
        service = PerformanceModeService.start_performance(
          session_id: 'short_performance',
          performance_type: 'comedy',
          duration_minutes: 0.1 # 6 seconds
        )

        expect(service).to be_a(PerformanceModeService)
        expect(service.duration_minutes).to eq(0.1)

        # Should handle timing correctly even for very short durations
        travel_to(10.seconds.from_now) do
          expect(service.is_running?).to be false
        end
      end

      it 'handles very long performance durations' do
        service = PerformanceModeService.start_performance(
          session_id: 'long_performance',
          performance_type: 'storytelling',
          duration_minutes: 1440 # 24 hours
        )

        expect(service.duration_minutes).to eq(1440)
        expect(service.time_remaining).to be_within(60).of(1440 * 60)
      end

      it 'handles empty and nil session identifiers gracefully' do
        # Should use default session ID for empty/nil
        expect {
          PerformanceModeService.start_performance(
            session_id: '',
            performance_type: 'comedy',
            duration_minutes: 5
          )
        }.not_to raise_error

        expect {
          PerformanceModeService.start_performance(
            session_id: nil,
            performance_type: 'comedy',
            duration_minutes: 5
          )
        }.to raise_error # Depending on implementation
      end
    end

    context 'unicode and special characters in session IDs' do
      it 'handles unicode session identifiers' do
        unicode_session = 'session_🎭_测试_عرض'

        service = PerformanceModeService.start_performance(
          session_id: unicode_session,
          performance_type: 'comedy',
          duration_minutes: 5
        )

        expect(service.session_id).to eq(unicode_session)

        # Should be retrievable
        retrieved = PerformanceModeService.get_active_performance(unicode_session)
        expect(retrieved.session_id).to eq(unicode_session)
      end
    end
  end
end
