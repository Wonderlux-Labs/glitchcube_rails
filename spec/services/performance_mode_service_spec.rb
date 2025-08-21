# spec/services/performance_mode_service_spec.rb

require 'rails_helper'

RSpec.describe PerformanceModeService, type: :service do
  let(:session_id) { 'test_performance_session' }
  let(:default_options) do
    {
      session_id: session_id,
      performance_type: 'comedy',
      duration_minutes: 2, # Short duration for tests
      prompt: 'Custom test prompt for comedy routine'
    }
  end

  before do
    # Clear cache before each test
    Rails.cache.clear
    # Clear any existing conversation logs
    ConversationLog.where(session_id: session_id).delete_all
  end

  after do
    # Cleanup: stop any running performances
    PerformanceModeService.stop_active_performance(session_id)
    Rails.cache.clear
  end

  describe '.start_performance', vcr: { cassette_name: 'performance_mode/start_performance' } do
    it 'creates and starts a new performance' do
      service = PerformanceModeService.start_performance(**default_options)

      expect(service).to be_a(PerformanceModeService)
      expect(service.session_id).to eq(session_id)
      expect(service.performance_type).to eq('comedy')
      expect(service.duration_minutes).to eq(2)
    end

    it 'stores performance state in cache' do
      PerformanceModeService.start_performance(**default_options)

      cached_state = Rails.cache.read("performance_mode:#{session_id}")
      expect(cached_state).to be_present
      expect(cached_state[:session_id]).to eq(session_id)
      expect(cached_state[:performance_type]).to eq('comedy')
      expect(cached_state[:is_running]).to be true
    end

    it 'enqueues background job' do
      expect { PerformanceModeService.start_performance(**default_options) }
        .to have_enqueued_job(PerformanceModeJob)
        .with(
          session_id: session_id,
          performance_type: 'comedy',
          duration_minutes: 2,
          prompt: 'Custom test prompt for comedy routine',
          persona: nil
        )
    end
  end

  describe '#start_performance', vcr: { cassette_name: 'performance_mode/instance_start' } do
    let(:service) { PerformanceModeService.new(**default_options) }

    it 'sets timing and running state correctly' do
      freeze_time do
        service.start_performance

        expect(service.instance_variable_get(:@start_time)).to eq(Time.current)
        expect(service.instance_variable_get(:@end_time)).to eq(Time.current + 2.minutes)
        expect(service.instance_variable_get(:@is_running)).to be true
      end
    end

    it 'logs performance start information' do
      expect(Rails.logger).to receive(:info).with(/Starting comedy performance for 2 minutes/)
      expect(Rails.logger).to receive(:info).with(/Prompt: Custom test prompt/)
      expect(Rails.logger).to receive(:info).with(/Performance mode started/)

      service.start_performance
    end
  end

  describe '#stop_performance', vcr: { cassette_name: 'performance_mode/stop_performance' } do
    let(:service) { PerformanceModeService.new(**default_options) }

    before do
      service.start_performance
    end

    context 'with manual stop reason' do
      it 'stops the performance and updates state' do
        service.stop_performance('manual_stop')

        expect(service.instance_variable_get(:@should_stop)).to be true
        expect(service.instance_variable_get(:@is_running)).to be false
        expect(service.instance_variable_get(:@end_time)).to be_within(1.second).of(Time.current)
      end

      it 'logs the stop reason' do
        expect(Rails.logger).to receive(:info).with('🛑 Performance stopped: manual_stop')
        service.stop_performance('manual_stop')
      end

      it 'does not send final performance segment' do
        expect(service).not_to receive(:send_performance_segment)
        service.stop_performance('manual_stop')
      end
    end

    context 'with wake word interrupt reason' do
      it 'sends interruption acknowledgment' do
        expect(service).to receive(:send_performance_segment)
          .with(/Oh! Looks like someone wants to chat!/, segment_type: 'interruption_acknowledgment')

        service.stop_performance('wake_word_interrupt')
      end
    end

    context 'with time expired reason' do
      it 'sends performance finale' do
        expect(service).to receive(:send_performance_segment)
          .with(/And that's a wrap on tonight's show!/, segment_type: 'performance_finale')

        service.stop_performance('time_expired')
      end
    end
  end

  describe '#interrupt_for_wake_word', vcr: { cassette_name: 'performance_mode/wake_word_interrupt' } do
    let(:service) { PerformanceModeService.new(**default_options) }

    before do
      service.start_performance
    end

    it 'sets wake word interruption flag and stops performance' do
      service.interrupt_for_wake_word

      expect(service.instance_variable_get(:@wake_word_interruption)).to be true
      expect(service.instance_variable_get(:@should_stop)).to be true
      expect(service.instance_variable_get(:@is_running)).to be false
    end

    it 'logs wake word interruption' do
      expect(Rails.logger).to receive(:info).with('🎤 Performance interrupted by wake word')
      service.interrupt_for_wake_word
    end
  end

  describe '#is_running?' do
    let(:service) { PerformanceModeService.new(**default_options) }

    context 'when performance is active' do
      before do
        service.start_performance
      end

      it 'returns true when running and not stopped and time remaining' do
        expect(service.is_running?).to be true
      end

      it 'returns false when should_stop is true' do
        service.instance_variable_set(:@should_stop, true)
        expect(service.is_running?).to be false
      end

      it 'returns false when not running' do
        service.instance_variable_set(:@is_running, false)
        expect(service.is_running?).to be false
      end

      it 'returns false when time has expired' do
        travel_to(3.minutes.from_now) do
          expect(service.is_running?).to be false
        end
      end
    end
  end

  describe '#time_remaining' do
    let(:service) { PerformanceModeService.new(**default_options) }

    it 'returns 0 when not running' do
      expect(service.time_remaining).to eq(0)
    end

    it 'returns remaining seconds when running' do
      freeze_time do
        service.start_performance

        travel_to(30.seconds.from_now) do
          expect(service.time_remaining).to eq(90) # 2 minutes - 30 seconds
        end
      end
    end
  end

  describe '#run_performance_loop', vcr: { cassette_name: 'performance_mode/performance_loop' } do
    let(:service) { PerformanceModeService.new(session_id: session_id, duration_minutes: 1) }

    before do
      service.instance_variable_set(:@start_time, Time.current)
      service.instance_variable_set(:@end_time, Time.current + 1.minute)
      service.instance_variable_set(:@is_running, true)
      service.instance_variable_set(:@should_stop, false)
      service.instance_variable_set(:@performance_segments, [])

      # Mock sleep to speed up tests
      allow(service).to receive(:sleep)
    end

    context 'with successful segment generation' do
      let(:mock_segment) do
        {
          speech_text: "Welcome to my comedy routine! Here's a joke about AI customer service...",
          segment_type: 'opening'
        }
      end

      before do
        allow(service).to receive(:generate_performance_segment).and_return(mock_segment)
        allow(service).to receive(:send_performance_segment)
        allow(service).to receive(:calculate_segment_duration).and_return(10)
      end

      it 'generates and sends performance segments' do
        # Mock the loop to run only once
        allow(service).to receive(:is_running?).and_return(true, false)

        expect(service).to receive(:generate_performance_segment)
        expect(service).to receive(:send_performance_segment)
          .with(mock_segment[:speech_text], segment_type: 'performance_segment')

        service.run_performance_loop
      end

      it 'stores segment information' do
        allow(service).to receive(:is_running?).and_return(true, false)

        service.run_performance_loop

        segments = service.instance_variable_get(:@performance_segments)
        expect(segments).to have(1).item
        expect(segments.first[:speech]).to eq(mock_segment[:speech_text])
        expect(segments.first[:segment]).to eq(1)
      end

      it 'calculates segment duration and sleeps appropriately' do
        allow(service).to receive(:is_running?).and_return(true, false)

        expect(service).to receive(:calculate_segment_duration)
          .with(mock_segment[:speech_text]).and_return(15)
        expect(service).to receive(:sleep).with(15)

        service.run_performance_loop
      end
    end

    context 'with failed segment generation' do
      before do
        allow(service).to receive(:generate_performance_segment).and_return(nil)
      end

      it 'handles failed generation gracefully' do
        allow(service).to receive(:is_running?).and_return(true, false)

        expect(Rails.logger).to receive(:warn).with(/Failed to generate performance segment/)
        expect(service).to receive(:sleep).with(10) # Default retry sleep

        service.run_performance_loop
      end
    end

    context 'when time expires naturally' do
      it 'stops performance with time_expired reason' do
        # Mock time progression
        allow(service).to receive(:is_running?).and_return(true, true, false)
        allow(service).to receive(:generate_performance_segment).and_return(nil)

        expect(service).to receive(:stop_performance).with('time_expired')

        service.run_performance_loop
      end
    end
  end

  describe '#generate_performance_segment', vcr: { cassette_name: 'performance_mode/generate_segment' } do
    let(:service) { PerformanceModeService.new(**default_options) }
    let(:context) do
      {
        performance_type: 'comedy',
        segment_number: 1,
        time_elapsed_seconds: 30,
        time_remaining_minutes: 1.5,
        is_opening: true,
        is_middle: false,
        is_closing: false
      }
    end

    context 'with successful LLM response' do
      let(:mock_response) do
        {
          speech_text: "Hey everyone! So I'm BUDDY, your friendly neighborhood AI who just crash-landed at Burning Man...",
          segment_type: 'opening'
        }
      end

      before do
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech).and_return(mock_response)
      end

      it 'generates segment using ContextualSpeechTriggerService' do
        expect_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech)
          .with(
            trigger_type: 'performance_segment',
            context: hash_including(:performance_context),
            persona: nil,
            force_response: true
          )

        result = service.send(:generate_performance_segment, context)
        expect(result).to eq(mock_response)
      end

      it 'logs successful generation' do
        expect(Rails.logger).to receive(:info).with(/Generated performance segment/)
        service.send(:generate_performance_segment, context)
      end
    end

    context 'with empty LLM response' do
      before do
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech).and_return({ speech_text: '' })
      end

      it 'returns nil for empty response' do
        expect(Rails.logger).to receive(:error).with(/Empty or invalid performance segment/)

        result = service.send(:generate_performance_segment, context)
        expect(result).to be_nil
      end
    end

    context 'with LLM service error' do
      before do
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech).and_raise(StandardError, 'LLM service unavailable')
      end

      it 'handles errors gracefully' do
        expect(Rails.logger).to receive(:error).with(/Error generating performance segment/)

        result = service.send(:generate_performance_segment, context)
        expect(result).to be_nil
      end
    end
  end

  describe '#send_performance_segment', vcr: { cassette_name: 'performance_mode/send_segment' } do
    let(:service) { PerformanceModeService.new(**default_options) }
    let(:speech_text) { "This is a test performance segment for the audience!" }

    before do
      service.start_performance
      allow_any_instance_of(HomeAssistantService)
        .to receive(:send_conversation_response)
    end

    it 'creates conversation log entry' do
      expect {
        service.send(:send_performance_segment, speech_text, segment_type: 'performance_segment')
      }.to change(ConversationLog, :count).by(1)

      log = ConversationLog.last
      expect(log.session_id).to eq(session_id)
      expect(log.user_message).to eq('[PERFORMANCE_MODE_PERFORMANCE_SEGMENT]')
      expect(log.ai_response).to eq(speech_text)

      metadata = JSON.parse(log.metadata)
      expect(metadata['performance_mode']).to be true
      expect(metadata['performance_type']).to eq('comedy')
      expect(metadata['segment_type']).to eq('performance_segment')
    end

    it 'sends to Home Assistant service' do
      expect_any_instance_of(HomeAssistantService)
        .to receive(:send_conversation_response)
        .with(hash_including(
          conversation_id: session_id,
          performance_mode: true,
          segment_type: 'performance_segment',
          response: hash_including(
            speech: hash_including(
              plain: hash_including(speech: speech_text)
            )
          )
        ))

      service.send(:send_performance_segment, speech_text, segment_type: 'performance_segment')
    end

    it 'logs successful broadcast' do
      expect(Rails.logger).to receive(:info).with(/Broadcasting performance segment/)
      expect(Rails.logger).to receive(:info).with(/Performance segment broadcast successfully/)

      service.send(:send_performance_segment, speech_text)
    end

    context 'when Home Assistant call fails' do
      before do
        allow_any_instance_of(HomeAssistantService)
          .to receive(:send_conversation_response)
          .and_raise(StandardError, 'HA connection failed')
      end

      it 'logs error but continues' do
        expect(Rails.logger).to receive(:error).with(/Failed to send performance segment/)

        expect {
          service.send(:send_performance_segment, speech_text)
        }.not_to raise_error
      end
    end
  end

  describe '.get_active_performance' do
    context 'with stored performance state' do
      let(:stored_state) do
        {
          session_id: session_id,
          performance_type: 'comedy',
          duration_minutes: 10,
          prompt: 'Test prompt',
          persona: nil,
          start_time: 1.minute.ago,
          end_time: 9.minutes.from_now,
          is_running: true,
          should_stop: false,
          segments_count: 2,
          last_updated: Time.current
        }
      end

      before do
        Rails.cache.write("performance_mode:#{session_id}", stored_state, expires_in: 2.hours)
      end

      it 'reconstructs service from cached state' do
        service = PerformanceModeService.get_active_performance(session_id)

        expect(service).to be_a(PerformanceModeService)
        expect(service.session_id).to eq(session_id)
        expect(service.performance_type).to eq('comedy')
        expect(service.duration_minutes).to eq(10)
        expect(service.instance_variable_get(:@is_running)).to be true
      end
    end

    context 'with no stored state' do
      it 'returns nil' do
        service = PerformanceModeService.get_active_performance('nonexistent_session')
        expect(service).to be_nil
      end
    end
  end

  describe '.stop_active_performance' do
    before do
      PerformanceModeService.start_performance(**default_options)
    end

    it 'stops existing performance and returns true' do
      result = PerformanceModeService.stop_active_performance(session_id, 'test_stop')
      expect(result).to be true

      # Verify performance is stopped
      service = PerformanceModeService.get_active_performance(session_id)
      expect(service.instance_variable_get(:@should_stop)).to be true
    end

    it 'returns false for nonexistent session' do
      result = PerformanceModeService.stop_active_performance('nonexistent', 'test_stop')
      expect(result).to be false
    end
  end

  describe 'private methods' do
    let(:service) { PerformanceModeService.new(**default_options) }

    describe '#default_prompt_for_type' do
      it 'returns comedy prompt for comedy type' do
        prompt = service.send(:default_prompt_for_type, 'comedy')
        expect(prompt).to include('stand-up comedy routine')
        expect(prompt).to include('Burning Man')
        expect(prompt).to include('BUDDY persona')
      end

      it 'returns storytelling prompt for storytelling type' do
        prompt = service.send(:default_prompt_for_type, 'storytelling')
        expect(prompt).to include('epic story')
        expect(prompt).to include('adventures in space')
      end

      it 'returns generic prompt for unknown type' do
        prompt = service.send(:default_prompt_for_type, 'unknown')
        expect(prompt).to include('unknown routine')
      end
    end

    describe '#calculate_segment_duration' do
      it 'calculates duration based on word count' do
        text = 'This is a test sentence with exactly ten words total'
        # 10 words / 150 wpm * 60 seconds + 10 second buffer = ~14 seconds
        duration = service.send(:calculate_segment_duration, text)
        expect(duration).to be_within(5).of(14)
      end

      it 'caps maximum duration at 60 seconds' do
        long_text = ('word ' * 200).strip # 200 words
        duration = service.send(:calculate_segment_duration, long_text)
        expect(duration).to eq(60)
      end
    end

    describe '#extract_themes_from_previous_segments' do
      before do
        segments = [
          { speech: 'Welcome to Burning Man! The playa is amazing!' },
          { speech: 'As an AI in space, I had many galactic adventures.' },
          { speech: 'Customer service was my specialty across the universe.' }
        ]
        service.instance_variable_set(:@performance_segments, segments)
      end

      it 'extracts themes from previous segments' do
        themes = service.send(:extract_themes_from_previous_segments)
        expect(themes).to include('burning man')
        expect(themes).to include('space adventures')
        expect(themes).to include('customer service')
      end

      it 'returns empty array when no segments' do
        service.instance_variable_set(:@performance_segments, [])
        themes = service.send(:extract_themes_from_previous_segments)
        expect(themes).to be_empty
      end
    end
  end

  describe 'different performance types', vcr: { cassette_name: 'performance_mode/different_types' } do
    %w[comedy storytelling poetry improv].each do |type|
      it "handles #{type} performance type correctly" do
        service = PerformanceModeService.new(
          session_id: "#{type}_session",
          performance_type: type,
          duration_minutes: 1
        )

        expect(service.performance_type).to eq(type)

        # Each type should have appropriate default prompt
        prompt = service.instance_variable_get(:@prompt)
        case type
        when 'comedy'
          expect(prompt).to include('stand-up comedy')
        when 'storytelling'
          expect(prompt).to include('epic story')
        when 'poetry'
          expect(prompt).to include('series of poems')
        when 'improv'
          expect(prompt).to include('improvisational performance')
        end
      end
    end
  end
end
