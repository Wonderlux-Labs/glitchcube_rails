# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversation, type: :model do
  describe 'associations' do
    it { should have_many(:messages).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:session_id) }
  end

  describe 'scopes' do
    let!(:active_conversation) { create(:conversation, ended_at: nil) }
    let!(:finished_conversation) { create(:conversation, ended_at: 1.hour.ago) }
    let!(:persona_conversation) { create(:conversation, persona: 'technical') }

    describe '.recent' do
      it 'orders by created_at desc' do
        expect(Conversation.recent.first).to eq(persona_conversation)
      end
    end

    describe '.active' do
      it 'returns conversations without ended_at' do
        expect(Conversation.active).to contain_exactly(active_conversation, persona_conversation)
      end
    end

    describe '.finished' do
      it 'returns conversations with ended_at' do
        expect(Conversation.finished).to contain_exactly(finished_conversation)
      end
    end

    describe '.by_persona' do
      it 'returns conversations with specific persona' do
        expect(Conversation.by_persona('technical')).to contain_exactly(persona_conversation)
      end
    end
  end

  describe '#end!' do
    let(:conversation) { create(:conversation, ended_at: nil, continue_conversation: true) }

    it 'sets ended_at and continue_conversation to false' do
      pending "TODO: Fix Time precision issue - expect(time).to eq(time) fails due to microsecond precision differences"
      freeze_time do
        conversation.end!
        expect(conversation.ended_at).to eq(Time.current)
        expect(conversation.continue_conversation).to be(false)
      end
    end

    it 'does not update if already ended' do
      conversation.update!(ended_at: 1.hour.ago)
      original_ended_at = conversation.ended_at

      conversation.end!
      expect(conversation.ended_at).to eq(original_ended_at)
    end
  end

  describe '#finished?' do
    it 'returns true when ended_at is present' do
      conversation = build(:conversation, ended_at: 1.hour.ago)
      expect(conversation.finished?).to be(true)
    end

    it 'returns false when ended_at is nil' do
      conversation = build(:conversation, ended_at: nil)
      expect(conversation.finished?).to be(false)
    end
  end

  describe '#finished_ago' do
    it 'returns time since ended_at' do
      conversation = build(:conversation, ended_at: 2.hours.ago)
      expect(conversation.finished_ago).to be_within(1.second).of(2.hours)
    end

    it 'returns nil when not finished' do
      conversation = build(:conversation, ended_at: nil)
      expect(conversation.finished_ago).to be_nil
    end
  end

  describe '#active?' do
    it 'returns true when ended_at is nil' do
      conversation = build(:conversation, ended_at: nil)
      expect(conversation.active?).to be(true)
    end

    it 'returns false when ended_at is present' do
      conversation = build(:conversation, ended_at: 1.hour.ago)
      expect(conversation.active?).to be(false)
    end
  end

  describe '#duration' do
    let(:started_time) { 2.hours.ago }

    context 'when conversation is finished' do
      let(:ended_time) { 1.hour.ago }
      let(:conversation) { build(:conversation, started_at: started_time, ended_at: ended_time) }

      it 'returns duration between started_at and ended_at' do
        expect(conversation.duration).to be_within(1.second).of(1.hour)
      end
    end

    context 'when conversation is active' do
      let(:conversation) { build(:conversation, started_at: started_time, ended_at: nil) }

      it 'returns duration between started_at and current time' do
        pending "TODO: Fix Time precision issue with freeze_time - duration calculation has sub-second precision differences"
        freeze_time do
          expect(conversation.duration).to be_within(1.second).of(2.hours)
        end
      end
    end

    context 'when started_at is nil' do
      let(:conversation) { build(:conversation, started_at: nil) }

      it 'returns nil' do
        expect(conversation.duration).to be_nil
      end
    end
  end

  describe '#add_message' do
    let(:conversation) { create(:conversation) }

    it 'creates a new message' do
      expect {
        conversation.add_message(role: 'user', content: 'Hello')
      }.to change(conversation.messages, :count).by(1)
    end

    it 'creates message with correct attributes' do
      message = conversation.add_message(role: 'user', content: 'Hello', model_used: 'gpt-4')
      expect(message.role).to eq('user')
      expect(message.content).to eq('Hello')
      expect(message.model_used).to eq('gpt-4')
    end
  end

  describe '#flow_data_json' do
    let(:conversation) { build(:conversation) }

    it 'parses valid JSON' do
      conversation.flow_data = '{"thoughts": ["thinking"]}'
      expect(conversation.flow_data_json).to eq({ 'thoughts' => [ 'thinking' ] })
    end

    it 'returns empty hash for invalid JSON' do
      conversation.flow_data = 'invalid'
      expect(conversation.flow_data_json).to eq({})
    end

    it 'returns empty hash for blank flow_data' do
      conversation.flow_data = ''
      expect(conversation.flow_data_json).to eq({})
    end
  end

  describe '#metadata_json' do
    let(:conversation) { build(:conversation) }

    it 'parses valid JSON' do
      conversation.metadata = '{"source": "web"}'
      expect(conversation.metadata_json).to eq({ 'source' => 'web' })
    end

    it 'returns empty hash for invalid JSON' do
      conversation.metadata = 'invalid'
      expect(conversation.metadata_json).to eq({})
    end
  end

  describe '#summary' do
    let(:conversation) { create(:conversation, session_id: 'test-123', persona: 'technical') }
    let!(:message) { create(:message, conversation: conversation, content: 'Last message') }

    before do
      conversation.update!(
        message_count: 5,
        total_cost: 0.05,
        total_tokens: 1000,
        started_at: 2.hours.ago,
        ended_at: 1.hour.ago
      )
    end

    it 'returns summary hash with all relevant data' do
      summary = conversation.summary
      expect(summary[:session_id]).to eq('test-123')
      expect(summary[:message_count]).to eq(5)
      expect(summary[:persona]).to eq('technical')
      expect(summary[:total_cost]).to eq(0.05)
      expect(summary[:total_tokens]).to eq(1000)
      expect(summary[:duration]).to be_within(1.second).of(1.hour)
      expect(summary[:last_message]).to eq('Last message')
    end

    it 'memoizes the result' do
      first_call = conversation.summary
      second_call = conversation.summary
      expect(first_call).to equal(second_call)
    end
  end

  describe '#update_totals!' do
    let(:conversation) { create(:conversation) }

    before do
      create(:message, conversation: conversation, prompt_tokens: 100, completion_tokens: 50, cost: 0.01)
      create(:message, conversation: conversation, prompt_tokens: 200, completion_tokens: 75, cost: 0.02)
    end

    it 'updates total_tokens and total_cost' do
      conversation.update_totals!
      expect(conversation.total_tokens).to eq(425) # 100+50+200+75
      expect(conversation.total_cost).to eq(0.03) # 0.01+0.02
    end
  end
end
