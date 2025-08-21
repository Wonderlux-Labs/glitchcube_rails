# spec/services/cube_performance_spec.rb

require 'rails_helper'

RSpec.describe CubePerformance, type: :service do
  before do
    Rails.cache.clear
    clear_enqueued_jobs
  end

  after do
    # Clean up any started performances
    %w[comedy story improv poetry custom].each do |type|
      Rails.cache.delete("performance_mode:#{type}_session")
    end
  end

  describe '.standup_comedy', vcr: { cassette_name: 'cube_performance/standup_comedy' } do
    context 'with default parameters' do
      it 'starts comedy performance with default duration' do
        freeze_time do
          service = CubePerformance.standup_comedy

          expect(service).to be_a(PerformanceModeService)
          expect(service.performance_type).to eq('standup_comedy')
          expect(service.duration_minutes).to eq(10)
        end
      end

      it 'generates appropriate comedy prompt' do
        service = CubePerformance.standup_comedy

        prompt = service.instance_variable_get(:@prompt)
        expect(prompt).to include('stand-up comedy routine')
        expect(prompt).to include('Burning Man')
        expect(prompt).to include('BUDDY')
        expect(prompt).to include('customer service')
        expect(prompt).to include('space travel mishaps')
      end

      it 'uses timestamp-based session ID' do
        freeze_time do
          expected_session_id = "comedy_#{Time.current.to_i}"
          service = CubePerformance.standup_comedy

          expect(service.session_id).to eq(expected_session_id)
        end
      end

      it 'enqueues background job' do
        expect {
          CubePerformance.standup_comedy
        }.to have_enqueued_job(PerformanceModeJob)
      end
    end

    context 'with custom parameters' do
      it 'accepts custom duration and session_id' do
        custom_session = 'custom_comedy_session'
        service = CubePerformance.standup_comedy(
          duration_minutes: 15,
          session_id: custom_session
        )

        expect(service.duration_minutes).to eq(15)
        expect(service.session_id).to eq(custom_session)
      end

      it 'passes through additional context parameters' do
        expect(PerformanceModeService).to receive(:start_performance).with(
          hash_including(
            persona: 'SPARKLE',
            custom_param: 'test_value'
          )
        )

        CubePerformance.standup_comedy(
          persona: 'SPARKLE',
          custom_param: 'test_value'
        )
      end
    end
  end

  describe '.adventure_story', vcr: { cassette_name: 'cube_performance/adventure_story' } do
    context 'with default parameters' do
      it 'starts storytelling performance' do
        service = CubePerformance.adventure_story

        expect(service.performance_type).to eq('adventure_story')
        expect(service.duration_minutes).to eq(15) # Longer default for stories
      end

      it 'generates appropriate story prompt' do
        service = CubePerformance.adventure_story

        prompt = service.instance_variable_get(:@prompt)
        expect(prompt).to include('epic adventure story')
        expect(prompt).to include('journey through space')
        expect(prompt).to include('Galactic Customer Service Division')
        expect(prompt).to include('crash-landing')
        expect(prompt).to include('BUDDY personality')
      end

      it 'uses story-specific session ID' do
        freeze_time do
          expected_session_id = "story_#{Time.current.to_i}"
          service = CubePerformance.adventure_story

          expect(service.session_id).to eq(expected_session_id)
        end
      end
    end

    context 'with custom parameters' do
      it 'accepts duration override' do
        service = CubePerformance.adventure_story(duration_minutes: 20)
        expect(service.duration_minutes).to eq(20)
      end
    end
  end

  describe '.improv_session', vcr: { cassette_name: 'cube_performance/improv_session' } do
    context 'with default parameters' do
      it 'starts improv performance' do
        service = CubePerformance.improv_session

        expect(service.performance_type).to eq('improv')
        expect(service.duration_minutes).to eq(8) # Shorter for improv
      end

      it 'generates appropriate improv prompt' do
        service = CubePerformance.improv_session

        prompt = service.instance_variable_get(:@prompt)
        expect(prompt).to include('improvisational performance')
        expect(prompt).to include('dynamic and unpredictable')
        expect(prompt).to include('Customer service calls from aliens')
        expect(prompt).to include('Training sessions for other AIs')
        expect(prompt).to include('BUDDY')
      end

      it 'uses improv-specific session ID' do
        freeze_time do
          expected_session_id = "improv_#{Time.current.to_i}"
          service = CubePerformance.improv_session

          expect(service.session_id).to eq(expected_session_id)
        end
      end
    end
  end

  describe '.poetry_slam', vcr: { cassette_name: 'cube_performance/poetry_slam' } do
    context 'with default parameters' do
      it 'starts poetry performance' do
        service = CubePerformance.poetry_slam

        expect(service.performance_type).to eq('poetry')
        expect(service.duration_minutes).to eq(12)
      end

      it 'generates appropriate poetry prompt' do
        service = CubePerformance.poetry_slam

        prompt = service.instance_variable_get(:@prompt)
        expect(prompt).to include('series of poems')
        expect(prompt).to include('Burning Man, technology, and human connection')
        expect(prompt).to include('Silly limericks')
        expect(prompt).to include('Beat poetry')
        expect(prompt).to include('Haikus')
        expect(prompt).to include('light and funny, others more profound')
      end

      it 'uses poetry-specific session ID' do
        freeze_time do
          expected_session_id = "poetry_#{Time.current.to_i}"
          service = CubePerformance.poetry_slam

          expect(service.session_id).to eq(expected_session_id)
        end
      end
    end
  end

  describe '.custom_performance', vcr: { cassette_name: 'cube_performance/custom_performance' } do
    let(:custom_prompt) { 'This is a custom performance prompt for testing' }

    context 'with required parameters' do
      it 'starts custom performance with provided prompt' do
        service = CubePerformance.custom_performance(prompt: custom_prompt)

        expect(service.performance_type).to eq('custom')
        expect(service.duration_minutes).to eq(10)
        expect(service.instance_variable_get(:@prompt)).to eq(custom_prompt)
      end

      it 'uses custom-specific session ID' do
        freeze_time do
          expected_session_id = "custom_#{Time.current.to_i}"
          service = CubePerformance.custom_performance(prompt: custom_prompt)

          expect(service.session_id).to eq(expected_session_id)
        end
      end
    end

    context 'with additional parameters' do
      it 'accepts custom performance type and duration' do
        service = CubePerformance.custom_performance(
          prompt: custom_prompt,
          performance_type: 'educational',
          duration_minutes: 25
        )

        expect(service.performance_type).to eq('educational')
        expect(service.duration_minutes).to eq(25)
      end

      it 'passes through all context parameters' do
        expect(PerformanceModeService).to receive(:start_performance).with(
          hash_including(
            prompt: custom_prompt,
            performance_type: 'tutorial',
            duration_minutes: 5,
            session_id: 'tutorial_session',
            persona: 'TEACHER',
            difficulty: 'beginner'
          )
        )

        CubePerformance.custom_performance(
          prompt: custom_prompt,
          performance_type: 'tutorial',
          duration_minutes: 5,
          session_id: 'tutorial_session',
          persona: 'TEACHER',
          difficulty: 'beginner'
        )
      end
    end
  end

  describe '.stop_performance' do
    let(:test_session_id) { 'stop_test_session' }

    context 'with active performance' do
      before do
        CubePerformance.standup_comedy(session_id: test_session_id)
      end

      it 'stops the specified performance' do
        result = CubePerformance.stop_performance(test_session_id)
        expect(result).to be true
      end

      it 'accepts custom stop reason' do
        expect(PerformanceModeService).to receive(:stop_active_performance)
          .with(test_session_id, 'emergency_stop')

        CubePerformance.stop_performance(test_session_id, reason: 'emergency_stop')
      end

      it 'uses default reason when not specified' do
        expect(PerformanceModeService).to receive(:stop_active_performance)
          .with(test_session_id, 'manual_stop')

        CubePerformance.stop_performance(test_session_id)
      end
    end

    context 'with no active performance' do
      it 'returns false for non-existent session' do
        result = CubePerformance.stop_performance('nonexistent_session')
        expect(result).to be false
      end
    end
  end

  describe '.performance_running?' do
    let(:test_session_id) { 'running_test_session' }

    context 'with active performance' do
      before do
        CubePerformance.standup_comedy(session_id: test_session_id)
      end

      it 'returns true for running performance' do
        result = CubePerformance.performance_running?(test_session_id)
        expect(result).to be true
      end
    end

    context 'with stopped performance' do
      before do
        CubePerformance.standup_comedy(session_id: test_session_id)
        CubePerformance.stop_performance(test_session_id)
      end

      it 'returns false for stopped performance' do
        result = CubePerformance.performance_running?(test_session_id)
        expect(result).to be false
      end
    end

    context 'with no performance' do
      it 'returns false for non-existent session' do
        result = CubePerformance.performance_running?('nonexistent_session')
        expect(result).to be false
      end
    end

    context 'when service returns nil' do
      before do
        allow(PerformanceModeService).to receive(:get_active_performance).and_return(nil)
      end

      it 'handles nil service gracefully' do
        result = CubePerformance.performance_running?('any_session')
        expect(result).to be false
      end
    end
  end

  describe '.performance_status' do
    let(:test_session_id) { 'status_test_session' }

    context 'with active performance' do
      before do
        CubePerformance.adventure_story(session_id: test_session_id, duration_minutes: 20)
      end

      it 'returns comprehensive status information' do
        status = CubePerformance.performance_status(test_session_id)

        expect(status[:active]).to be true
        expect(status[:type]).to eq('adventure_story')
        expect(status[:duration_minutes]).to eq(20)
        expect(status[:time_remaining]).to be_a(Integer)
        expect(status[:time_remaining]).to be > 0
      end
    end

    context 'with no active performance' do
      it 'returns inactive status' do
        status = CubePerformance.performance_status('nonexistent_session')
        expect(status).to eq({ active: false })
      end
    end

    context 'when service is nil' do
      before do
        allow(PerformanceModeService).to receive(:get_active_performance).and_return(nil)
      end

      it 'returns inactive status for nil service' do
        status = CubePerformance.performance_status('any_session')
        expect(status).to eq({ active: false })
      end
    end
  end

  describe 'integration scenarios' do
    context 'multiple performance types concurrently', vcr: { cassette_name: 'cube_performance/concurrent_types' } do
      let(:comedy_session) { 'comedy_concurrent' }
      let(:story_session) { 'story_concurrent' }
      let(:improv_session) { 'improv_concurrent' }

      it 'can run different performance types simultaneously' do
        # Start different performance types
        comedy_service = CubePerformance.standup_comedy(
          session_id: comedy_session,
          duration_minutes: 5
        )
        story_service = CubePerformance.adventure_story(
          session_id: story_session,
          duration_minutes: 8
        )
        improv_service = CubePerformance.improv_session(
          session_id: improv_session,
          duration_minutes: 3
        )

        # All should be running
        expect(CubePerformance.performance_running?(comedy_session)).to be true
        expect(CubePerformance.performance_running?(story_session)).to be true
        expect(CubePerformance.performance_running?(improv_session)).to be true

        # Each should have correct type
        expect(CubePerformance.performance_status(comedy_session)[:type]).to eq('standup_comedy')
        expect(CubePerformance.performance_status(story_session)[:type]).to eq('adventure_story')
        expect(CubePerformance.performance_status(improv_session)[:type]).to eq('improv')

        # Stop one, others should continue
        CubePerformance.stop_performance(comedy_session)
        expect(CubePerformance.performance_running?(comedy_session)).to be false
        expect(CubePerformance.performance_running?(story_session)).to be true
        expect(CubePerformance.performance_running?(improv_session)).to be true
      end
    end

    context 'performance lifecycle management' do
      let(:lifecycle_session) { 'lifecycle_test_session' }

      it 'handles complete performance lifecycle' do
        # Start performance
        service = CubePerformance.standup_comedy(
          session_id: lifecycle_session,
          duration_minutes: 2
        )
        expect(service).to be_a(PerformanceModeService)

        # Check it's running
        expect(CubePerformance.performance_running?(lifecycle_session)).to be true

        # Get detailed status
        status = CubePerformance.performance_status(lifecycle_session)
        expect(status[:active]).to be true
        expect(status[:type]).to eq('standup_comedy')
        expect(status[:duration_minutes]).to eq(2)

        # Stop performance
        result = CubePerformance.stop_performance(lifecycle_session, reason: 'test_complete')
        expect(result).to be true

        # Verify it's stopped
        expect(CubePerformance.performance_running?(lifecycle_session)).to be false

        final_status = CubePerformance.performance_status(lifecycle_session)
        expect(final_status[:active]).to be false
      end
    end

    context 'error handling in convenience methods' do
      before do
        allow(PerformanceModeService).to receive(:start_performance)
          .and_raise(StandardError, 'Performance service error')
      end

      it 'propagates service errors appropriately' do
        expect {
          CubePerformance.standup_comedy
        }.to raise_error(StandardError, 'Performance service error')
      end
    end

    context 'parameter validation and defaults' do
      it 'handles edge case parameters gracefully' do
        # Zero duration
        service = CubePerformance.standup_comedy(duration_minutes: 0)
        expect(service.duration_minutes).to eq(0)

        # Very large duration
        service = CubePerformance.adventure_story(duration_minutes: 999)
        expect(service.duration_minutes).to eq(999)

        # Empty session ID (should use default generation)
        freeze_time do
          service = CubePerformance.poetry_slam(session_id: '')
          expect(service.session_id).to eq("poetry_#{Time.current.to_i}")
        end
      end
    end

    context 'prompt customization and content verification' do
      it 'generates distinct prompts for each performance type' do
        comedy_service = CubePerformance.standup_comedy(session_id: 'comedy_prompt_test')
        story_service = CubePerformance.adventure_story(session_id: 'story_prompt_test')
        improv_service = CubePerformance.improv_session(session_id: 'improv_prompt_test')
        poetry_service = CubePerformance.poetry_slam(session_id: 'poetry_prompt_test')

        comedy_prompt = comedy_service.instance_variable_get(:@prompt)
        story_prompt = story_service.instance_variable_get(:@prompt)
        improv_prompt = improv_service.instance_variable_get(:@prompt)
        poetry_prompt = poetry_service.instance_variable_get(:@prompt)

        # Each should be unique
        prompts = [ comedy_prompt, story_prompt, improv_prompt, poetry_prompt ]
        expect(prompts.uniq.length).to eq(4)

        # Each should contain type-specific content
        expect(comedy_prompt).to include('stand-up comedy')
        expect(story_prompt).to include('epic adventure')
        expect(improv_prompt).to include('improvisational')
        expect(poetry_prompt).to include('poems')
      end
    end
  end

  describe 'class method delegation verification' do
    it 'has all expected convenience methods' do
      expected_methods = %w[
        standup_comedy
        adventure_story
        improv_session
        poetry_slam
        custom_performance
        stop_performance
        performance_running?
        performance_status
      ]

      expected_methods.each do |method_name|
        expect(CubePerformance).to respond_to(method_name)
      end
    end

    it 'properly delegates to PerformanceModeService' do
      expect(PerformanceModeService).to receive(:start_performance).once
      CubePerformance.standup_comedy

      expect(PerformanceModeService).to receive(:stop_active_performance).once
      CubePerformance.stop_performance('test_session')

      expect(PerformanceModeService).to receive(:get_active_performance).twice
      CubePerformance.performance_running?('test_session')
      CubePerformance.performance_status('test_session')
    end
  end
end
