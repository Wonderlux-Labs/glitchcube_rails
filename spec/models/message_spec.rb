# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Message, type: :model do
  describe 'associations' do
    it { should belong_to(:conversation).counter_cache(:message_count) }
  end

  describe 'validations' do
    it { should validate_presence_of(:role) }
    it { should validate_presence_of(:content) }
    it { should validate_inclusion_of(:role).in_array(%w[user assistant system]) }
  end

  describe 'scopes' do
    let(:conversation) { create(:conversation) }
    let!(:user_message) { create(:message, conversation: conversation, role: 'user') }
    let!(:assistant_message) { create(:message, conversation: conversation, role: 'assistant') }
    let!(:system_message) { create(:message, conversation: conversation, role: 'system') }

    describe '.by_role' do
      it 'returns messages with specific role' do
        expect(Message.by_role('user')).to contain_exactly(user_message)
        expect(Message.by_role('assistant')).to contain_exactly(assistant_message)
      end
    end

    describe '.recent' do
      it 'orders by created_at desc' do
        expect(Message.recent.first).to eq(system_message)
      end
    end

    describe '.chronological' do
      it 'orders by created_at asc' do
        expect(Message.chronological.first).to eq(user_message)
      end
    end
  end

  describe '#to_api_format' do
    let(:message) { build(:message, role: 'user', content: 'Hello AI') }

    it 'returns hash with role and content' do
      expect(message.to_api_format).to eq({
        role: 'user',
        content: 'Hello AI'
      })
    end
  end

  describe '#token_cost' do
    context 'with all required fields' do
      let(:message) do
        build(:message,
              prompt_tokens: 100,
              completion_tokens: 50,
              model_used: 'gpt-4')
      end

      it 'returns token cost hash' do
        expect(message.token_cost).to eq({
          prompt_tokens: 100,
          completion_tokens: 50,
          total_tokens: 150,
          model: 'gpt-4'
        })
      end
    end

    context 'with missing fields' do
      let(:message) { build(:message, prompt_tokens: nil) }

      it 'returns nil' do
        expect(message.token_cost).to be_nil
      end
    end
  end

  describe '#metadata_json' do
    let(:message) { build(:message) }

    context 'with valid JSON' do
      before { message.metadata = '{"temperature": 0.7, "max_tokens": 150}' }

      it 'parses JSON correctly' do
        expect(message.metadata_json).to eq({
          'temperature' => 0.7,
          'max_tokens' => 150
        })
      end
    end

    context 'with invalid JSON' do
      before { message.metadata = 'invalid json' }

      it 'returns empty hash' do
        expect(message.metadata_json).to eq({})
      end
    end

    context 'with blank metadata' do
      before { message.metadata = '' }

      it 'returns empty hash' do
        expect(message.metadata_json).to eq({})
      end
    end
  end

  describe '#metadata_json=' do
    let(:message) { build(:message) }

    it 'converts hash to JSON string' do
      message.metadata_json = { temperature: 0.7, max_tokens: 150 }
      expect(message.metadata).to eq('{"temperature":0.7,"max_tokens":150}')
    end
  end
end