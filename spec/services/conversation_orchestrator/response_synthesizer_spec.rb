# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationOrchestrator::ResponseSynthesizer do
  let(:llm_response) do
    {
      "speech" => "I've turned on the lights for you.",
      "continue_conversation" => false,
      "inner_monologue" => "User requested light control",
      "actions" => [ { "action_name" => "cube_light", "description" => "warm amber, dim" } ]
    }
  end

  let(:action_results) do
    {
      sync_results: {
        "lights.control" => { success: true, message: "Light turned on" }
      },
      delegated_intents: []
    }
  end

  let(:prompt_data) do
    {
      messages: [
        { role: "system", content: "You are a helpful assistant" },
        { role: "user", content: "Turn on the lights" }
      ],
      system_prompt: "You are a helpful assistant"
    }
  end

  describe '.call' do
    context 'with valid structured response' do
      it 'synthesizes a complete AI response' do
        result = described_class.call(
          llm_response: llm_response,
          action_results: action_results,
          prompt_data: prompt_data
        )

        expect(result.success?).to be true
        expect(result.data).to include(
          text: "I've turned on the lights for you.",
          continue_conversation: false,
          inner_monologue: "User requested light control",
          actions: [ { "action_name" => "cube_light", "description" => "warm amber, dim" } ],
          speech_text: "I've turned on the lights for you.",
          success: true
        )
        expect(result.data[:id]).to be_a(String)
      end
    end

    context 'when speech text is blank' do
      let(:llm_response) { { "speech" => "", "continue_conversation" => false } }
      let(:action_results) { { sync_results: {}, delegated_intents: [] } }

      it 'provides fallback speech text' do
        result = described_class.call(
          llm_response: llm_response,
          action_results: action_results,
          prompt_data: prompt_data
        )

        expect(result.success?).to be true
        expect(result.data[:text]).to eq("I understand.")
        expect(result.data[:speech_text]).to eq("I understand.")
      end
    end

    context 'with symbol keys in LLM response' do
      let(:llm_response) do
        {
          speech: "Hello there!",
          continue_conversation: true
        }
      end
      let(:action_results) { { sync_results: {}, delegated_intents: [] } }

      it 'handles symbol keys correctly' do
        result = described_class.call(
          llm_response: llm_response,
          action_results: action_results,
          prompt_data: prompt_data
        )

        expect(result.success?).to be true
        expect(result.data[:text]).to eq("Hello there!")
        expect(result.data[:continue_conversation]).to be true
      end
    end

    context 'when an error occurs during synthesis' do
      before do
        allow(SecureRandom).to receive(:uuid).and_raise(StandardError.new("UUID generation failed"))
      end

      it 'returns a failure result' do
        result = described_class.call(
          llm_response: llm_response,
          action_results: action_results,
          prompt_data: prompt_data
        )

        expect(result.success?).to be false
        expect(result.error).to include("Response synthesis failed")
      end
    end
  end
end
