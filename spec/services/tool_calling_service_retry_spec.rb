require 'rails_helper'

RSpec.describe ToolCallingService, type: :service do
  let(:session_id) { "test-session-#{SecureRandom.hex(4)}" }
  let(:conversation_id) { nil }
  let(:service) { described_class.new(session_id: session_id, conversation_id: conversation_id) }

  describe 'retry logic with validation errors' do
    context 'when LLM requests invalid effect' do
      it 'retries with error feedback and corrects the effect', :vcr do
        # Mock Home Assistant service to avoid real API calls during tool execution
        allow(HomeAssistantService).to receive(:call_service).and_return({ "success" => true })
        allow(HomeAssistantService).to receive(:entity).and_return({ "state" => "off" })

        # Mock logger to track retry attempts
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)
        allow(Rails.logger).to receive(:error)

        # Test intent that should trigger an invalid effect initially
        intent = "Turn on some super space desert UFO mode lighting effects"
        context = { persona: "jax" }

        # Execute the intent - this should trigger retry logic
        result = service.execute_intent(intent, context)

        # The result should be a string response
        expect(result).to be_a(String)

        # Should not be a complete failure - either success or reasonable attempt
        expect(result).not_to eq("I'm having trouble with that right now.")

        # Verify logs show retry attempts
        expect(Rails.logger).to have_received(:info).with(/🔄 Tool calling attempt/)
      end
    end

    context 'when effects tool returns validation error' do
      it 'extracts validation errors and retries with feedback' do
        # Mock the LLM response for both attempts
        mock_llm_response = double('llm_response',
          tool_calls: [
            double('tool_call',
              name: "control_effects",
              arguments: { "effect" => "space_desert_ufo", "action" => "on" }
            )
          ]
        )

        allow(service).to receive(:call_tool_calling_llm).and_return(mock_llm_response)

        # Mock tool execution - first fails, second succeeds
        call_count = 0
        allow(service).to receive(:execute_tool_calls) do |tool_calls|
          call_count += 1

          if call_count == 1
            # First attempt - validation error
            {
              "control_effects" => {
                success: false,
                error: "Unknown effect: space_desert_ufo",
                available_effects: [ "fan", "strobe", "blacklight", "siren" ]
              }
            }
          else
            # Second attempt - success
            {
              "control_effects" => {
                success: true,
                message: "Turned on strobe effect"
              }
            }
          end
        end

        intent = "Activate the space desert UFO effect"
        context = { persona: "jax" }

        result = service.execute_intent(intent, context)

        # Should have called LLM twice (original + retry)
        expect(service).to have_received(:call_tool_calling_llm).twice

        # Should have called execute_tool_calls twice
        expect(service).to have_received(:execute_tool_calls).twice

        # Final result should be a string response
        expect(result).to be_a(String)
        expect(result).to be_present
      end
    end

    context 'max iterations configuration' do
      it 'respects configured max_iterations' do
        # Set a custom max iterations
        allow(Rails.configuration).to receive(:try).with(:tool_calling_max_iterations).and_return(2)

        service = described_class.new(session_id: session_id)
        expect(service.instance_variable_get(:@max_iterations)).to eq(2)
      end

      it 'uses default max_iterations when not configured' do
        allow(Rails.configuration).to receive(:try).with(:tool_calling_max_iterations).and_return(nil)

        service = described_class.new(session_id: session_id)
        expect(service.instance_variable_get(:@max_iterations)).to eq(4)
      end
    end
  end

  describe 'validation error extraction' do
    let(:service) { described_class.new }

    context 'with control_effects error' do
      it 'extracts available effects from error response' do
        results = {
          "control_effects" => {
            success: false,
            error: "Unknown effect: space_mode",
            available_effects: [ "fan", "strobe", "blacklight", "siren" ]
          }
        }

        errors = service.send(:extract_validation_errors, results)

        expect(errors.length).to eq(1)
        expect(errors.first).to include(
          tool: "control_effects",
          error: "Unknown effect: space_mode",
          available_options: [ "fan", "strobe", "blacklight", "siren" ]
        )
      end
    end

    context 'with mode_control error' do
      it 'extracts available modes from error response' do
        results = {
          "mode_control" => {
            success: false,
            error: "Unknown mode: party_mode",
            available_modes: [ "normal", "party", "sleep", "focus" ]
          }
        }

        errors = service.send(:extract_validation_errors, results)

        expect(errors.length).to eq(1)
        expect(errors.first).to include(
          tool: "mode_control",
          error: "Unknown mode: party_mode",
          available_options: [ "normal", "party", "sleep", "focus" ]
        )
      end
    end
  end

  describe 'retry intent building' do
    let(:service) { described_class.new }

    it 'builds corrective feedback with available options' do
      original_intent = "Turn on space mode effects"
      validation_errors = [
        {
          tool: "control_effects",
          error: "Unknown effect: space_mode",
          available_options: [ "fan", "strobe", "blacklight", "siren" ]
        }
      ]

      retry_intent = service.send(:build_retry_intent, original_intent, validation_errors)

      expect(retry_intent).to include(original_intent)
      expect(retry_intent).to include("IMPORTANT CORRECTIONS NEEDED")
      expect(retry_intent).to include("Unknown effect: space_mode")
      expect(retry_intent).to include("Available options: [\"fan\", \"strobe\", \"blacklight\", \"siren\"]")
    end
  end
end
