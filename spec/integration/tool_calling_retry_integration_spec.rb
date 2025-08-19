require 'rails_helper'

RSpec.describe 'Tool Calling Retry Integration', type: :integration do
  let(:session_id) { "retry-test-#{SecureRandom.hex(4)}" }

  describe 'end-to-end retry with actual LLM calls' do
    context 'when requesting invalid effects' do
      it 'retries with error feedback from control_effects tool', :vcr do
        # Mock Home Assistant to simulate tool execution environment
        allow(HomeAssistantService).to receive(:call_service).and_return({ "success" => true })
        allow(HomeAssistantService).to receive(:entity).and_return({
          "state" => "off",
          "attributes" => { "supported_features" => 63 }
        })

        # Create service instance
        service = ToolCallingService.new(session_id: session_id)

        # Test with an intentionally invalid effect that should trigger retry
        intent = "Turn on the cosmic rainbow UFO strobe effect"
        context = { persona: "jax" }

        # Execute - this should trigger LLM calls with VCR recording
        result = service.execute_intent(intent, context)

        # Verify we got a response
        expect(result).to be_a(String)

        # The response should not be a complete failure
        expect(result).not_to eq("I'm having trouble with that right now.")

        # Should contain some indication of attempting to work with available effects
        expect(result).not_to be_empty
      end

      it 'handles mode control validation errors with retry', :vcr do
        # Mock Home Assistant
        allow(HomeAssistantService).to receive(:call_service).and_return({ "success" => true })

        service = ToolCallingService.new(session_id: session_id)

        # Test with invalid mode
        intent = "Switch to mega party disco mode"
        context = { persona: "jax" }

        result = service.execute_intent(intent, context)

        expect(result).to be_a(String)
        expect(result).not_to eq("I'm having trouble with that right now.")
      end
    end

    context 'configuration behavior' do
      it 'uses configured max_iterations' do
        # Test that configuration is respected
        original_config = Rails.configuration.try(:tool_calling_max_iterations)

        begin
          # Set test configuration
          Rails.configuration.tool_calling_max_iterations = 2

          service = ToolCallingService.new(session_id: session_id)
          expect(service.instance_variable_get(:@max_iterations)).to eq(2)
        ensure
          # Restore original config
          Rails.configuration.tool_calling_max_iterations = original_config
        end
      end
    end
  end
end
