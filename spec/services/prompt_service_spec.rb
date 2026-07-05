# spec/services/prompt_service_spec.rb
require 'rails_helper'

RSpec.describe PromptService do
  let(:conversation) { create(:conversation) }
  let(:persona) { 'buddy' }
  let(:extra_context) { {} }
  let(:user_message) { "Hello there!" }

  before do
    allow(HaDataSync).to receive(:entity_state).with("sensor.cube_mode").and_return("active")
    allow(HaDataSync).to receive(:get_context_attribute).and_return(nil)
    allow(CubePersona).to receive(:current_persona).and_return(persona)
  end

  describe '.build_prompt_for' do
    subject do
      described_class.build_prompt_for(
        persona: persona,
        conversation: conversation,
        extra_context: extra_context,
        user_message: user_message
      )
    end

    it 'returns a hash with expected keys' do
      expect(subject).to be_a(Hash)
      expect(subject).to have_key(:system_prompt)
      expect(subject).to have_key(:messages)
      expect(subject).to have_key(:tools)
      expect(subject).to have_key(:context)
    end

    it 'delegates to modular builders correctly' do
      expect(Prompts::PersonaLoader).to receive(:load).and_call_original
      expect(Prompts::SystemPromptBuilder).to receive(:build).and_call_original
      expect(Prompts::MessageHistoryBuilder).to receive(:build).with(conversation).and_call_original

      subject
    end

    it 'creates ContextBuilder with correct parameters' do
      expect(Prompts::ContextBuilder).to receive(:new).with(
        conversation: conversation,
        extra_context: extra_context,
        user_message: user_message
      ).and_call_original

      subject
    end

    context 'system prompt content' do
      it 'includes persona-specific content' do
        expect(subject[:system_prompt]).to be_present
        expect(subject[:system_prompt]).to be_a(String)
      end

      it 'includes context information' do
        expect(subject[:system_prompt]).to include('# CURRENT CONTEXT')
      end
    end

    context 'tools' do
      it 'returns empty array as the brain emits an environment_instruction instead of tool calls' do
        expect(subject[:tools]).to eq([])
      end
    end

    context 'messages' do
      it 'returns message history from builder' do
        expect(subject[:messages]).to be_an(Array)
      end
    end

    context 'context' do
      it 'returns context from builder' do
        expect(subject[:context]).to be_present
      end
    end
  end

  describe 'message ordering' do
    let(:conversation_with_messages) { create(:conversation, :with_conversation_logs) }

    it 'ensures system prompt comes first and messages are only user/assistant' do
      result = described_class.build_prompt_for(
        persona: persona,
        conversation: conversation_with_messages,
        extra_context: extra_context
      )

      expect(result[:system_prompt]).to be_present
      expect(result[:messages]).to be_an(Array)

      result[:messages].each do |message|
        expect(message[:role]).to be_in([ 'user', 'assistant' ])
      end
    end
  end

  describe 'error handling' do
    context 'when conversation is nil' do
      it 'still builds prompt' do
        result = described_class.build_prompt_for(
          persona: persona,
          conversation: nil,
          extra_context: extra_context
        )

        expect(result[:system_prompt]).to be_present
        expect(result[:messages]).to eq([])
        expect(result[:tools]).to eq([])
        expect(result[:context]).to be_present
      end
    end

    context 'when persona is nil' do
      it 'defaults to current persona from CubePersona' do
        expect(CubePersona).to receive(:current_persona).and_return('buddy')

        result = described_class.build_prompt_for(
          persona: nil,
          conversation: conversation,
          extra_context: extra_context
        )

        expect(result).to have_key(:system_prompt)
      end
    end
  end
end
