# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationNewOrchestrator::PromptBuilder do
  let(:conversation) { instance_double(Conversation, id: 123, metadata_json: nil) }
  let(:persona) { instance_double(CubePersona, name: "Assistant") }
  let(:user_message) { "Turn on the lights" }
  let(:context) { { user_id: "user123", source: "home_assistant" } }

  let(:mock_prompt_data) do
    {
      messages: [
        { role: "system", content: "You are a helpful assistant" },
        { role: "user", content: user_message }
      ],
      system_prompt: "You are a helpful assistant"
    }
  end

  describe '.call' do
    context 'with valid parameters' do
      before do
        allow(PromptService).to receive(:build_prompt_for)
          .with(
            persona: persona,
            conversation: conversation,
            extra_context: context,
            user_message: user_message
          )
          .and_return(mock_prompt_data)
      end

      it 'builds prompt successfully using PromptService' do
        result = described_class.call(
          conversation: conversation,
          persona: persona,
          user_message: user_message,
          context: context
        )

        expect(result.success?).to be true
        expect(result.data).to eq(mock_prompt_data)
        expect(PromptService).to have_received(:build_prompt_for)
      end
    end

    context 'with pending HA results in conversation metadata' do
      let(:metadata_with_results) do
        {
          "pending_ha_results" => [
            {
              "id" => "result_1",
              "tool" => "light.turn_on",
              "tool_intents" => [ { "intent" => "turn on lights" } ],
              "ha_response" => {
                "response" => {
                  "data" => {
                    "success" => [ { "name" => "Living Room Light" } ],
                    "failed" => []
                  }
                }
              },
              "timestamp" => 1.minute.ago.to_f,
              "processed" => false
            }
          ]
        }
      end

      before do
        allow(conversation).to receive(:metadata_json).and_return(metadata_with_results)
        allow(conversation).to receive(:update!)
        allow(PromptService).to receive(:build_prompt_for).and_return(mock_prompt_data.dup)
      end

      it 'injects HA results into the prompt and clears them' do
        result = described_class.call(
          conversation: conversation,
          persona: persona,
          user_message: user_message,
          context: context
        )

        expect(result.success?).to be true

        # Should have injected the HA result as a system message
        messages = result.data[:messages]
        injected_message = messages.find { |msg| msg[:role] == "system" && msg[:content].include?("turn on lights") }
        expect(injected_message).to be_present

        # Should have marked the results as processed
        expect(conversation).to have_received(:update!).with(
          metadata_json: hash_including(
            "pending_ha_results" => array_including(
              hash_including("processed" => true)
            )
          )
        )
      end
    end

    context 'with stale HA results (older than 5 minutes)' do
      let(:metadata_with_stale_results) do
        {
          "pending_ha_results" => [
            {
              "id" => "stale_result",
              "tool" => "old.tool",
              "result" => { "success" => true },
              "timestamp" => 10.minutes.ago.to_f,
              "processed" => false
            }
          ]
        }
      end

      before do
        allow(conversation).to receive(:metadata_json).and_return(metadata_with_stale_results)
        allow(conversation).to receive(:update!)
        allow(PromptService).to receive(:build_prompt_for).and_return(mock_prompt_data.dup)
      end

      it 'ignores stale results and clears them' do
        result = described_class.call(
          conversation: conversation,
          persona: persona,
          user_message: user_message,
          context: context
        )

        expect(result.success?).to be true

        # Should not have injected stale results
        messages = result.data[:messages]
        injected_message = messages.find { |msg| msg[:role] == "system" && msg[:content].include?("old.tool") }
        expect(injected_message).to be_nil

        # Should have marked the stale results as processed
        expect(conversation).to have_received(:update!).with(
          metadata_json: hash_including(
            "pending_ha_results" => array_including(
              hash_including("processed" => true)
            )
          )
        )
      end
    end

    context 'when PromptService raises an error' do
      before do
        allow(PromptService).to receive(:build_prompt_for)
          .and_raise(StandardError.new("Prompt service failed"))
      end

      it 'returns a failure result' do
        result = described_class.call(
          conversation: conversation,
          persona: persona,
          user_message: user_message,
          context: context
        )

        expect(result.success?).to be false
        expect(result.error).to include("Prompt building failed")
      end
    end

    context 'when conversation has no metadata' do
      before do
        allow(conversation).to receive(:metadata_json).and_return(nil)
        allow(PromptService).to receive(:build_prompt_for).and_return(mock_prompt_data)
      end

      it 'proceeds normally without trying to inject HA results' do
        result = described_class.call(
          conversation: conversation,
          persona: persona,
          user_message: user_message,
          context: context
        )

        expect(result.success?).to be true
        expect(result.data).to eq(mock_prompt_data)
      end
    end

    context 'when conversation has empty pending_ha_results' do
      let(:empty_metadata) { { "pending_ha_results" => [] } }

      before do
        allow(conversation).to receive(:metadata_json).and_return(empty_metadata)
        allow(PromptService).to receive(:build_prompt_for).and_return(mock_prompt_data)
      end

      it 'proceeds normally without injection' do
        result = described_class.call(
          conversation: conversation,
          persona: persona,
          user_message: user_message,
          context: context
        )

        expect(result.success?).to be true
        expect(result.data).to eq(mock_prompt_data)
      end
    end
  end
end
