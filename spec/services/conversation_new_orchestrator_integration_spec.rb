# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationNewOrchestrator do
  let(:session_id) { 'test_session_123' }
  let(:user_message) { 'Turn on the living room lights' }
  let(:context) { { user_id: 'user123', device_type: 'mobile' } }
  let(:orchestrator) { described_class.new }

  describe '#execute' do
    context 'when processing a new conversation' do
      it 'executes the full conversation pipeline successfully' do
        # Setup service should initialize conversation state
        expect_any_instance_of(ConversationSetupService).to receive(:execute)
          .with(session_id: session_id, context: context)
          .and_return(ServiceResult.success({
            session_id: session_id,
            conversation_log: instance_double(ConversationLog, id: 1),
            persona: instance_double(CubePersona, name: 'Assistant')
          }))

        # LLM Intention should analyze user intent
        expect_any_instance_of(LlmIntentionService).to receive(:execute)
          .with(hash_including(message: user_message, session_id: session_id))
          .and_return(ServiceResult.success({
            intention: 'control_device',
            confidence: 0.9,
            entities: [ { type: 'device', value: 'living room lights' } ],
            requires_tools: true
          }))

        # Action Executor should handle tool execution
        expect_any_instance_of(ActionExecutorService).to receive(:execute)
          .with(hash_including(
            intention: 'control_device',
            entities: [ { type: 'device', value: 'living room lights' } ],
            message: user_message
          ))
          .and_return(ServiceResult.success({
            tool_results: [ { tool: 'light_control', success: true, message: 'Lights turned on' } ],
            execution_summary: 'Successfully turned on living room lights'
          }))

        # Response Synthesizer should generate natural language response
        expect_any_instance_of(ResponseSynthesizerService).to receive(:execute)
          .with(hash_including(
            original_message: user_message,
            tool_results: [ { tool: 'light_control', success: true, message: 'Lights turned on' } ],
            intention: 'control_device'
          ))
          .and_return(ServiceResult.success({
            response_text: "I've turned on the living room lights for you.",
            response_type: 'success',
            suggestions: [ 'Turn off lights', 'Dim lights to 50%' ]
          }))

        # Finalizer should save state and prepare final response
        expect_any_instance_of(ConversationFinalizerService).to receive(:execute)
          .with(hash_including(
            session_id: session_id,
            response_text: "I've turned on the living room lights for you.",
            conversation_log: instance_of(ConversationLog)
          ))
          .and_return(ServiceResult.success({
            conversation_id: 1,
            saved: true
          }))

        result = orchestrator.execute(
          session_id: session_id,
          message: user_message,
          context: context
        )

        expect(result).to be_success
        expect(result.data).to include(
          response: "I've turned on the living room lights for you.",
          conversation_id: 1,
          suggestions: [ 'Turn off lights', 'Dim lights to 50%' ]
        )
      end
    end

    context 'when processing a continuing conversation' do
      let(:existing_conversation) { create(:conversation_log, session_id: session_id) }

      it 'maintains conversation context across turns' do
        expect_any_instance_of(ConversationSetupService).to receive(:execute)
          .and_return(ServiceResult.success({
            session_id: session_id,
            conversation_log: existing_conversation,
            persona: instance_double(CubePersona, name: 'Assistant'),
            conversation_history: [ 'Previous turn about temperature' ]
          }))

        expect_any_instance_of(LlmIntentionService).to receive(:execute)
          .with(hash_including(
            message: user_message,
            conversation_history: [ 'Previous turn about temperature' ]
          ))
          .and_return(ServiceResult.success({
            intention: 'control_device',
            confidence: 0.95,
            entities: [],
            requires_tools: true
          }))

        allow_any_instance_of(ActionExecutorService).to receive(:execute)
          .and_return(ServiceResult.success({ tool_results: [], execution_summary: '' }))

        allow_any_instance_of(ResponseSynthesizerService).to receive(:execute)
          .and_return(ServiceResult.success({
            response_text: 'Done!',
            response_type: 'success'
          }))

        allow_any_instance_of(ConversationFinalizerService).to receive(:execute)
          .and_return(ServiceResult.success({ conversation_id: existing_conversation.id }))

        result = orchestrator.execute(
          session_id: session_id,
          message: user_message,
          context: context
        )

        expect(result).to be_success
      end
    end

    context 'when no tools are required' do
      it 'skips action execution for conversational responses' do
        allow_any_instance_of(ConversationSetupService).to receive(:execute)
          .and_return(ServiceResult.success({
            session_id: session_id,
            conversation_log: instance_double(ConversationLog),
            persona: instance_double(CubePersona, name: 'Assistant')
          }))

        expect_any_instance_of(LlmIntentionService).to receive(:execute)
          .and_return(ServiceResult.success({
            intention: 'casual_conversation',
            confidence: 0.8,
            entities: [],
            requires_tools: false
          }))

        # Action Executor should not be called when no tools are required
        expect(ActionExecutorService).not_to receive(:new)

        expect_any_instance_of(ResponseSynthesizerService).to receive(:execute)
          .with(hash_including(
            intention: 'casual_conversation',
            tool_results: []
          ))
          .and_return(ServiceResult.success({
            response_text: "Hello! How can I help you today?",
            response_type: 'conversational'
          }))

        allow_any_instance_of(ConversationFinalizerService).to receive(:execute)
          .and_return(ServiceResult.success({ conversation_id: 1 }))

        result = orchestrator.execute(
          session_id: session_id,
          message: 'Hello there!',
          context: context
        )

        expect(result).to be_success
        expect(result.data[:response]).to eq("Hello! How can I help you today?")
      end
    end

    context 'when setup service fails' do
      it 'returns error without calling subsequent services' do
        expect_any_instance_of(ConversationSetupService).to receive(:execute)
          .and_return(ServiceResult.failure('Failed to initialize conversation'))

        # No other services should be called
        expect(LlmIntentionService).not_to receive(:new)
        expect(ActionExecutorService).not_to receive(:new)
        expect(ResponseSynthesizerService).not_to receive(:new)
        expect(ConversationFinalizerService).not_to receive(:new)

        result = orchestrator.execute(
          session_id: session_id,
          message: user_message,
          context: context
        )

        expect(result).to be_failure
        expect(result.error).to eq('Failed to initialize conversation')
      end
    end

    context 'when LLM intention service fails' do
      it 'returns error after setup but before action execution' do
        allow_any_instance_of(ConversationSetupService).to receive(:execute)
          .and_return(ServiceResult.success({ session_id: session_id }))

        expect_any_instance_of(LlmIntentionService).to receive(:execute)
          .and_return(ServiceResult.failure('Failed to analyze user intent'))

        # Later services should not be called
        expect(ActionExecutorService).not_to receive(:new)
        expect(ResponseSynthesizerService).not_to receive(:new)

        # But finalizer should still be called to handle error state
        expect_any_instance_of(ConversationFinalizerService).to receive(:execute)
          .with(hash_including(error: true))
          .and_return(ServiceResult.success({}))

        result = orchestrator.execute(
          session_id: session_id,
          message: user_message,
          context: context
        )

        expect(result).to be_failure
        expect(result.error).to eq('Failed to analyze user intent')
      end
    end

    context 'when action executor fails' do
      it 'continues with error state to response synthesis' do
        allow_any_instance_of(ConversationSetupService).to receive(:execute)
          .and_return(ServiceResult.success({ session_id: session_id }))

        allow_any_instance_of(LlmIntentionService).to receive(:execute)
          .and_return(ServiceResult.success({
            intention: 'control_device',
            requires_tools: true
          }))

        expect_any_instance_of(ActionExecutorService).to receive(:execute)
          .and_return(ServiceResult.failure('Device not found'))

        # Response synthesizer should handle the error case
        expect_any_instance_of(ResponseSynthesizerService).to receive(:execute)
          .with(hash_including(
            error: true,
            error_message: 'Device not found'
          ))
          .and_return(ServiceResult.success({
            response_text: "I'm sorry, I couldn't find that device.",
            response_type: 'error'
          }))

        allow_any_instance_of(ConversationFinalizerService).to receive(:execute)
          .and_return(ServiceResult.success({}))

        result = orchestrator.execute(
          session_id: session_id,
          message: user_message,
          context: context
        )

        expect(result).to be_success
        expect(result.data[:response]).to eq("I'm sorry, I couldn't find that device.")
      end
    end

    context 'when response synthesizer fails' do
      it 'returns a generic error response' do
        allow_any_instance_of(ConversationSetupService).to receive(:execute)
          .and_return(ServiceResult.success({ session_id: session_id }))

        allow_any_instance_of(LlmIntentionService).to receive(:execute)
          .and_return(ServiceResult.success({ requires_tools: false }))

        expect_any_instance_of(ResponseSynthesizerService).to receive(:execute)
          .and_return(ServiceResult.failure('Failed to generate response'))

        expect_any_instance_of(ConversationFinalizerService).to receive(:execute)
          .with(hash_including(error: true))
          .and_return(ServiceResult.success({}))

        result = orchestrator.execute(
          session_id: session_id,
          message: user_message,
          context: context
        )

        expect(result).to be_failure
        expect(result.error).to eq('Failed to generate response')
      end
    end

    context 'when finalizer fails' do
      it 'still returns the response but logs the finalization error' do
        allow_any_instance_of(ConversationSetupService).to receive(:execute)
          .and_return(ServiceResult.success({ session_id: session_id }))

        allow_any_instance_of(LlmIntentionService).to receive(:execute)
          .and_return(ServiceResult.success({ requires_tools: false }))

        allow_any_instance_of(ResponseSynthesizerService).to receive(:execute)
          .and_return(ServiceResult.success({
            response_text: 'Hello!',
            response_type: 'success'
          }))

        expect_any_instance_of(ConversationFinalizerService).to receive(:execute)
          .and_return(ServiceResult.failure('Failed to save conversation'))

        # Should log the error but still return success with response
        expect(Rails.logger).to receive(:error).with(/Failed to finalize conversation/)

        result = orchestrator.execute(
          session_id: session_id,
          message: user_message,
          context: context
        )

        expect(result).to be_success
        expect(result.data[:response]).to eq('Hello!')
        expect(result.data[:finalization_error]).to eq('Failed to save conversation')
      end
    end

    context 'with complex multi-tool scenario' do
      it 'handles multiple tool executions and complex response synthesis' do
        allow_any_instance_of(ConversationSetupService).to receive(:execute)
          .and_return(ServiceResult.success({
            session_id: session_id,
            conversation_log: instance_double(ConversationLog),
            persona: instance_double(CubePersona, name: 'Assistant')
          }))

        allow_any_instance_of(LlmIntentionService).to receive(:execute)
          .and_return(ServiceResult.success({
            intention: 'complex_automation',
            confidence: 0.9,
            entities: [
              { type: 'room', value: 'living room' },
              { type: 'action', value: 'movie mode' }
            ],
            requires_tools: true
          }))

        expect_any_instance_of(ActionExecutorService).to receive(:execute)
          .and_return(ServiceResult.success({
            tool_results: [
              { tool: 'light_control', success: true, message: 'Lights dimmed to 20%' },
              { tool: 'climate_control', success: true, message: 'Temperature set to 72°F' },
              { tool: 'media_control', success: false, message: 'TV not responding' }
            ],
            execution_summary: 'Partially completed movie mode setup'
          }))

        expect_any_instance_of(ResponseSynthesizerService).to receive(:execute)
          .with(hash_including(
            tool_results: array_including(
              hash_including(success: true),
              hash_including(success: false)
            )
          ))
          .and_return(ServiceResult.success({
            response_text: "I've set up movie mode - dimmed the lights and adjusted temperature, but the TV isn't responding.",
            response_type: 'partial_success',
            suggestions: [ 'Try turning on TV manually', 'Check TV connection' ]
          }))

        allow_any_instance_of(ConversationFinalizerService).to receive(:execute)
          .and_return(ServiceResult.success({ conversation_id: 1 }))

        result = orchestrator.execute(
          session_id: session_id,
          message: 'Set up movie mode in the living room',
          context: context
        )

        expect(result).to be_success
        expect(result.data[:response]).to include('movie mode')
        expect(result.data[:suggestions]).to include('Try turning on TV manually')
      end
    end
  end

  describe 'Home Assistant compatibility' do
    it 'returns response format compatible with Home Assistant voice assistant' do
      # Mock all services to return successful responses
      allow_any_instance_of(ConversationSetupService).to receive(:execute)
        .and_return(ServiceResult.success({ session_id: session_id }))

      allow_any_instance_of(LlmIntentionService).to receive(:execute)
        .and_return(ServiceResult.success({ requires_tools: false }))

      allow_any_instance_of(ResponseSynthesizerService).to receive(:execute)
        .and_return(ServiceResult.success({
          response_text: 'The temperature is 72 degrees.',
          response_type: 'informational',
          suggestions: [ 'Set temperature to 75', 'Turn on fan' ]
        }))

      allow_any_instance_of(ConversationFinalizerService).to receive(:execute)
        .and_return(ServiceResult.success({ conversation_id: 1 }))

      result = orchestrator.execute(
        session_id: session_id,
        message: 'What is the temperature?',
        context: context
      )

      expect(result).to be_success

      # Verify Home Assistant compatible response structure
      expect(result.data).to include(
        response: be_a(String),
        conversation_id: be_a(Integer)
      )

      # Optional fields that Home Assistant can use
      expect(result.data).to have_key(:suggestions) # For follow-up actions

      # Response should be a plain string for TTS
      expect(result.data[:response]).to eq('The temperature is 72 degrees.')
    end

    it 'handles errors gracefully for Home Assistant integration' do
      allow_any_instance_of(ConversationSetupService).to receive(:execute)
        .and_return(ServiceResult.failure('Service unavailable'))

      result = orchestrator.execute(
        session_id: session_id,
        message: user_message,
        context: context
      )

      expect(result).to be_failure
      expect(result.error).to be_present

      # Even errors should be structured for Home Assistant
      expect(result.error).to be_a(String)
    end
  end

  describe 'state management between services' do
    it 'passes accumulated state through the pipeline correctly' do
      setup_data = {
        session_id: session_id,
        conversation_log: instance_double(ConversationLog, id: 1),
        persona: instance_double(CubePersona, name: 'Assistant')
      }

      intention_data = {
        intention: 'get_weather',
        confidence: 0.9,
        entities: [ { type: 'location', value: 'San Francisco' } ],
        requires_tools: true
      }

      action_data = {
        tool_results: [ { tool: 'weather', success: true, data: { temp: 72, condition: 'sunny' } } ],
        execution_summary: 'Retrieved weather data'
      }

      expect_any_instance_of(ConversationSetupService).to receive(:execute)
        .and_return(ServiceResult.success(data: setup_data))

      expect_any_instance_of(LlmIntentionService).to receive(:execute)
        .with(hash_including(setup_data))
        .and_return(ServiceResult.success(data: intention_data))

      expect_any_instance_of(ActionExecutorService).to receive(:execute)
        .with(hash_including(setup_data.merge(intention_data)))
        .and_return(ServiceResult.success(data: action_data))

      expect_any_instance_of(ResponseSynthesizerService).to receive(:execute)
        .with(hash_including(
          setup_data.merge(intention_data).merge(action_data).merge(
            original_message: user_message
          )
        ))
        .and_return(ServiceResult.success({
          response_text: "It's 72°F and sunny in San Francisco.",
          response_type: 'informational'
        }))

      expect_any_instance_of(ConversationFinalizerService).to receive(:execute)
        .with(hash_including(
          response_text: "It's 72°F and sunny in San Francisco.",
          conversation_log: setup_data[:conversation_log]
        ))
        .and_return(ServiceResult.success({ conversation_id: 1 }))

      result = orchestrator.execute(
        session_id: session_id,
        message: user_message,
        context: context
      )

      expect(result).to be_success
    end
  end

  describe 'performance and resource management' do
    it 'times out gracefully on long-running operations' do
      # This test would verify timeout behavior once implemented
      expect(orchestrator).to respond_to(:execute)
    end

    it 'handles concurrent requests with the same session_id' do
      # This test would verify thread safety once implemented
      expect(orchestrator).to respond_to(:execute)
    end
  end
end
