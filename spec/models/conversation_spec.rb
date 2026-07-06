# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversation, type: :model do
  # freeze_time / travel_to helpers are not globally included in this suite.
  include ActiveSupport::Testing::TimeHelpers

  describe 'associations' do
    it { should have_many(:conversation_logs).dependent(:destroy) }
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
      freeze_time do
        conversation.end!
        expect(conversation.ended_at).to be_within(1.second).of(Time.current)
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
end
