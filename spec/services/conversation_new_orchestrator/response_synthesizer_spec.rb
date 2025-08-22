# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationNewOrchestrator::ResponseSynthesizer do
  let(:llm_response) do
    {
      "speech_text" => "I've turned on the lights for you.",
      "continue_conversation" => false,
      "inner_thoughts" => "User requested light control",
      "current_mood" => "helpful",
      "pressing_questions" => nil,
      "goal_progress" => nil
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
          inner_thoughts: "User requested light control",
          current_mood: "helpful",
          speech_text: "I've turned on the lights for you.",
          success: true
        )
        expect(result.data[:id]).to be_a(String)
      end
    end

    context 'when speech text is blank' do
      let(:llm_response) { { "speech_text" => "", "continue_conversation" => false } }
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

    context 'with query tool results' do
      let(:action_results) do
        {
          sync_results: {
            "rag_search" => { success: true, message: "Found 3 lighting rules" }
          },
          delegated_intents: []
        }
      end

      before do
        allow(Tools::Registry).to receive(:tool_intent).with("rag_search").and_return(:query)
        allow(LlmService).to receive(:call_with_tools).and_return(
          double(content: "I've turned on the lights based on your preferences I found.")
        )
      end

      it 'amends speech with query results' do
        result = described_class.call(
          llm_response: llm_response,
          action_results: action_results,
          prompt_data: prompt_data
        )

        expect(result.success?).to be true
        expect(result.data[:text]).to eq("I've turned on the lights based on your preferences I found.")
        expect(LlmService).to have_received(:call_with_tools)
      end
    end

    context 'when speech amendment fails' do
      let(:action_results) do
        {
          sync_results: {
            "rag_search" => { success: true, message: "Found settings" }
          },
          delegated_intents: []
        }
      end

      before do
        allow(Tools::Registry).to receive(:tool_intent).with("rag_search").and_return(:query)
        allow(LlmService).to receive(:call_with_tools).and_raise(StandardError.new("LLM error"))
      end

      it 'falls back to original speech' do
        result = described_class.call(
          llm_response: llm_response,
          action_results: action_results,
          prompt_data: prompt_data
        )

        expect(result.success?).to be true
        expect(result.data[:text]).to eq("I've turned on the lights for you.")
      end
    end

    context 'with symbol keys in LLM response' do
      let(:llm_response) do
        {
          speech_text: "Hello there!",
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
