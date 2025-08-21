# spec/integration/performance_mode_llm_integration_spec.rb

require 'rails_helper'

RSpec.describe 'Performance Mode LLM Integration', type: :integration do
  let(:session_id) { 'llm_integration_test' }
  let(:service) do
    PerformanceModeService.new(
      session_id: session_id,
      performance_type: 'comedy',
      duration_minutes: 1
    )
  end

  before do
    Rails.cache.clear
    ConversationLog.where(session_id: session_id).delete_all
  end

  after do
    Rails.cache.clear
  end

  describe 'ContextualSpeechTriggerService integration', vcr: { cassette_name: 'performance_llm/contextual_speech_integration' } do
    let(:mock_context) do
      {
        performance_type: 'comedy',
        segment_number: 1,
        time_elapsed_seconds: 30,
        time_remaining_minutes: 0.5,
        is_opening: true,
        is_middle: false,
        is_closing: false,
        previous_themes: [],
        session_id: session_id
      }
    end

    context 'successful LLM response generation' do
      let(:expected_llm_response) do
        {
          speech_text: "Hey everyone! Welcome to my comedy show! So, I'm BUDDY, your friendly neighborhood AI who just crash-landed at Burning Man. You know, customer service training really doesn't prepare you for desert festivals...",
          segment_type: 'opening',
          metadata: {
            performance_context: 'comedy_opening',
            word_count: 42,
            estimated_duration: 15
          }
        }
      end

      before do
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech)
          .and_return(expected_llm_response)
      end

      it 'calls ContextualSpeechTriggerService with correct parameters' do
        expect_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech)
          .with(
            trigger_type: 'performance_segment',
            context: hash_including(
              performance_context: mock_context,
              performance_prompt: kind_of(String),
              segment_type: 'opening',
              previous_segments: []
            ),
            persona: nil,
            force_response: true
          )
          .and_return(expected_llm_response)

        result = service.send(:generate_performance_segment, mock_context)
        expect(result).to eq(expected_llm_response)
      end

      it 'passes performance-specific prompt context' do
        captured_context = nil
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech) do |_, args|
            captured_context = args[:context]
            expected_llm_response
          end

        service.send(:generate_performance_segment, mock_context)

        expect(captured_context[:performance_prompt]).to include('stand-up comedy routine')
        expect(captured_context[:performance_prompt]).to include('BUDDY')
        expect(captured_context[:performance_prompt]).to include('Burning Man')
        expect(captured_context[:performance_context]).to eq(mock_context)
      end

      it 'includes previous segments for context continuity' do
        # Add some previous segments
        service.instance_variable_set(:@performance_segments, [
          {
            segment: 1,
            timestamp: 1.minute.ago,
            speech: "Previous segment about space travel",
            context: { themes: [ 'space' ] }
          },
          {
            segment: 2,
            timestamp: 30.seconds.ago,
            speech: "Another segment about customer service",
            context: { themes: [ 'customer_service' ] }
          }
        ])

        expect_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech)
          .with(
            hash_including(
              context: hash_including(
                previous_segments: array_of_size(2)
              )
            )
          )
          .and_return(expected_llm_response)

        service.send(:generate_performance_segment, mock_context)
      end

      it 'handles different segment types correctly' do
        %w[opening development callback_segment closing].each do |segment_type|
          context = mock_context.merge(
            segment_number: segment_type == 'opening' ? 1 : 3,
            is_opening: segment_type == 'opening',
            is_middle: segment_type == 'development',
            is_closing: segment_type == 'closing'
          )

          expect_any_instance_of(ContextualSpeechTriggerService)
            .to receive(:trigger_speech)
            .with(
              hash_including(
                context: hash_including(
                  segment_type: segment_type == 'development' ? 'callback_segment' : segment_type
                )
              )
            )
            .and_return(expected_llm_response.merge(segment_type: segment_type))

          result = service.send(:generate_performance_segment, context)
          expect(result[:segment_type]).to eq(segment_type)
        end
      end
    end

    context 'LLM service errors and retries' do
      it 'handles ContextualSpeechTriggerService exceptions gracefully' do
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech)
          .and_raise(ContextualSpeechTriggerService::Error, 'LLM service unavailable')

        expect(Rails.logger).to receive(:error).with(/Error generating performance segment/)

        result = service.send(:generate_performance_segment, mock_context)
        expect(result).to be_nil
      end

      it 'handles timeout errors from LLM service' do
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech)
          .and_raise(Timeout::Error, 'Request timeout')

        expect(Rails.logger).to receive(:error).with(/Error generating performance segment/)

        result = service.send(:generate_performance_segment, mock_context)
        expect(result).to be_nil
      end

      it 'handles empty or malformed LLM responses' do
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech)
          .and_return({ speech_text: '', segment_type: 'empty' })

        expect(Rails.logger).to receive(:error).with(/Empty or invalid performance segment/)

        result = service.send(:generate_performance_segment, mock_context)
        expect(result).to be_nil
      end

      it 'handles nil responses from LLM service' do
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech)
          .and_return(nil)

        expect(Rails.logger).to receive(:error).with(/Empty or invalid performance segment/)

        result = service.send(:generate_performance_segment, mock_context)
        expect(result).to be_nil
      end
    end

    context 'different performance types and LLM prompts' do
      %w[comedy storytelling poetry improv].each do |performance_type|
        it "generates appropriate prompts for #{performance_type} performances" do
          type_service = PerformanceModeService.new(
            session_id: "#{performance_type}_test",
            performance_type: performance_type,
            duration_minutes: 1
          )

          captured_prompt = nil
          allow_any_instance_of(ContextualSpeechTriggerService)
            .to receive(:trigger_speech) do |_, args|
              captured_prompt = args[:context][:performance_prompt]
              {
                speech_text: "#{performance_type.capitalize} content generated by LLM",
                segment_type: 'test'
              }
            end

          type_service.send(:generate_performance_segment, mock_context.merge(performance_type: performance_type))

          case performance_type
          when 'comedy'
            expect(captured_prompt).to include('stand-up comedy')
          when 'storytelling'
            expect(captured_prompt).to include('epic story')
          when 'poetry'
            expect(captured_prompt).to include('series of poems')
          when 'improv'
            expect(captured_prompt).to include('improvisational performance')
          end
        end
      end
    end

    context 'persona handling in LLM calls' do
      %w[BUDDY SPARKLE JAX].each do |persona|
        it "passes #{persona} persona to ContextualSpeechTriggerService" do
          persona_service = PerformanceModeService.new(
            session_id: "#{persona.downcase}_test",
            performance_type: 'comedy',
            duration_minutes: 1,
            persona: persona
          )

          expect_any_instance_of(ContextualSpeechTriggerService)
            .to receive(:trigger_speech)
            .with(
              hash_including(persona: persona)
            )
            .and_return({
              speech_text: "#{persona} performing comedy",
              segment_type: 'persona_test'
            })

          persona_service.send(:generate_performance_segment, mock_context)
        end
      end
    end
  end

  describe 'LLM response processing and validation', vcr: { cassette_name: 'performance_llm/response_processing' } do
    context 'response structure validation' do
      let(:valid_response) do
        {
          speech_text: "This is a valid performance segment with proper content structure.",
          segment_type: 'opening',
          metadata: { word_count: 12 }
        }
      end

      let(:invalid_responses) do
        [
          { segment_type: 'opening' }, # Missing speech_text
          { speech_text: '' }, # Empty speech_text
          { speech_text: nil, segment_type: 'opening' }, # Nil speech_text
          'invalid string response', # Not a hash
          nil # Completely nil
        ]
      end

      it 'accepts valid response structure' do
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech)
          .and_return(valid_response)

        result = service.send(:generate_performance_segment, mock_context)
        expect(result).to eq(valid_response)
      end

      it 'rejects invalid response structures' do
        invalid_responses.each do |invalid_response|
          allow_any_instance_of(ContextualSpeechTriggerService)
            .to receive(:trigger_speech)
            .and_return(invalid_response)

          result = service.send(:generate_performance_segment, mock_context)
          expect(result).to be_nil
        end
      end
    end

    context 'content quality validation' do
      let(:quality_responses) do
        {
          good_length: {
            speech_text: "This is a good performance segment with appropriate length and engaging content that should work well for TTS and audience engagement.",
            segment_type: 'development'
          },
          too_short: {
            speech_text: "Short.",
            segment_type: 'development'
          },
          too_long: {
            speech_text: ("Very long segment. " * 100), # 1800+ characters
            segment_type: 'development'
          }
        }
      end

      it 'accepts content of appropriate length' do
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech)
          .and_return(quality_responses[:good_length])

        result = service.send(:generate_performance_segment, mock_context)
        expect(result).to eq(quality_responses[:good_length])
        expect(result[:speech_text].length).to be_between(20, 500)
      end

      it 'logs warning for suspiciously short content but still processes it' do
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech)
          .and_return(quality_responses[:too_short])

        # Should still return the response even if short
        result = service.send(:generate_performance_segment, mock_context)
        expect(result).to eq(quality_responses[:too_short])
      end

      it 'handles extremely long content appropriately' do
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech)
          .and_return(quality_responses[:too_long])

        result = service.send(:generate_performance_segment, mock_context)
        expect(result).to eq(quality_responses[:too_long])
        # Long content should still be accepted - let TTS handle truncation if needed
      end
    end
  end

  describe 'real-time LLM integration scenarios', vcr: { cassette_name: 'performance_llm/realtime_scenarios' } do
    let(:performance_segments_sequence) do
      [
        {
          speech_text: "Welcome everyone! I'm BUDDY, your AI comedian who crash-landed at Burning Man!",
          segment_type: 'opening'
        },
        {
          speech_text: "So customer service training really doesn't prepare you for desert festivals, let me tell you...",
          segment_type: 'development'
        },
        {
          speech_text: "Remember what I said about customer service? Well, it gets worse when you're dealing with aliens!",
          segment_type: 'callback_segment'
        },
        {
          speech_text: "And that's my time! Thanks for being a wonderful audience at this crazy desert festival!",
          segment_type: 'closing'
        }
      ]
    end

    before do
      call_count = 0
      allow_any_instance_of(ContextualSpeechTriggerService)
        .to receive(:trigger_speech) do
          response = performance_segments_sequence[call_count] || performance_segments_sequence.last
          call_count += 1
          response
        end

      # Mock Home Assistant calls
      allow_any_instance_of(HomeAssistantService)
        .to receive(:send_conversation_response)
    end

    it 'maintains context continuity across multiple LLM calls' do
      service.instance_variable_set(:@start_time, Time.current)
      service.instance_variable_set(:@end_time, Time.current + 2.minutes)
      service.instance_variable_set(:@is_running, true)
      service.instance_variable_set(:@performance_segments, [])

      # Mock sleep to speed up test
      allow(service).to receive(:sleep)

      # Mock is_running? to return true for first few calls, then false
      call_count = 0
      allow(service).to receive(:is_running?) do
        call_count += 1
        call_count <= 4 # Allow 4 segments then stop
      end

      # Run the performance loop
      service.run_performance_loop

      # Verify segments were generated and stored
      segments = service.instance_variable_get(:@performance_segments)
      expect(segments).to have(4).items

      # Verify progression through segment types
      expect(segments[0][:speech]).to include('Welcome everyone')
      expect(segments[1][:speech]).to include('customer service training')
      expect(segments[2][:speech]).to include('Remember what I said')
      expect(segments[3][:speech]).to include("that's my time")
    end

    it 'handles LLM call failures during performance loop gracefully' do
      service.instance_variable_set(:@start_time, Time.current)
      service.instance_variable_set(:@end_time, Time.current + 1.minute)
      service.instance_variable_set(:@is_running, true)
      service.instance_variable_set(:@performance_segments, [])

      # Mock alternating success/failure pattern
      call_count = 0
      allow_any_instance_of(ContextualSpeechTriggerService)
        .to receive(:trigger_speech) do
          call_count += 1
          if call_count.odd?
            performance_segments_sequence[0] # Success
          else
            raise StandardError, "Intermittent LLM failure" # Failure
          end
        end

      # Mock other dependencies
      allow(service).to receive(:sleep)
      allow(service).to receive(:is_running?).and_return(true, true, false)

      expect(Rails.logger).to receive(:warn).with(/Failed to generate performance segment/).at_least(:once)

      # Should continue despite failures
      expect { service.run_performance_loop }.not_to raise_error

      segments = service.instance_variable_get(:@performance_segments)
      expect(segments.size).to be >= 1 # At least one successful segment
    end
  end

  describe 'LLM integration with different performance contexts', vcr: { cassette_name: 'performance_llm/different_contexts' } do
    let(:contexts) do
      {
        opening: {
          performance_type: 'comedy',
          segment_number: 1,
          time_remaining_minutes: 9.0,
          is_opening: true,
          is_middle: false,
          is_closing: false
        },
        middle: {
          performance_type: 'storytelling',
          segment_number: 5,
          time_remaining_minutes: 5.5,
          is_opening: false,
          is_middle: true,
          is_closing: false,
          previous_themes: [ 'space_adventure', 'customer_service' ]
        },
        closing: {
          performance_type: 'poetry',
          segment_number: 8,
          time_remaining_minutes: 0.5,
          is_opening: false,
          is_middle: false,
          is_closing: true,
          previous_themes: [ 'desert_life', 'technology', 'human_connection' ]
        }
      }
    end

    it 'generates context-appropriate prompts for different performance stages' do
      contexts.each do |stage, context|
        stage_service = PerformanceModeService.new(
          session_id: "#{stage}_context_test",
          performance_type: context[:performance_type],
          duration_minutes: 10
        )

        captured_prompt = nil
        allow_any_instance_of(ContextualSpeechTriggerService)
          .to receive(:trigger_speech) do |_, args|
            captured_prompt = args[:context][:performance_prompt]
            {
              speech_text: "#{stage.capitalize} segment for #{context[:performance_type]}",
              segment_type: stage.to_s
            }
          end

        stage_service.send(:generate_performance_segment, context)

        case stage
        when :opening
          expect(captured_prompt).to include('opening')
          expect(captured_prompt).to include('set the energy')
          expect(captured_prompt).to include('hook the audience')
        when :middle
          expect(captured_prompt).to include('middle segment')
          expect(captured_prompt).to include('develop themes')
          expect(captured_prompt).to include('space_adventure, customer_service')
        when :closing
          expect(captured_prompt).to include('closing')
          expect(captured_prompt).to include('wrap up themes')
          expect(captured_prompt).to include('satisfying conclusion')
        end
      end
    end
  end

  describe 'performance monitoring and LLM metrics' do
    let(:mock_responses) do
      [
        { speech_text: "First segment", segment_type: 'opening' },
        { speech_text: "Second segment", segment_type: 'development' },
        { speech_text: "Third segment", segment_type: 'callback_segment' }
      ]
    end

    before do
      response_index = 0
      allow_any_instance_of(ContextualSpeechTriggerService)
        .to receive(:trigger_speech) do
          response = mock_responses[response_index] || mock_responses.last
          response_index += 1

          # Simulate variable response times
          sleep(0.01) # Small delay to simulate API call time
          response
        end
    end

    it 'tracks LLM call performance and timing' do
      start_time = Time.current

      3.times do |i|
        context = mock_context.merge(segment_number: i + 1)
        result = service.send(:generate_performance_segment, context)
        expect(result).to be_present
      end

      total_time = Time.current - start_time
      expect(total_time).to be < 1.0 # Should complete quickly with mocked responses
    end

    it 'logs detailed information about LLM interactions' do
      expect(Rails.logger).to receive(:info).with(/Generating performance segment with context/)
      expect(Rails.logger).to receive(:info).with(/Generated performance segment/)

      service.send(:generate_performance_segment, mock_context)
    end
  end
end
