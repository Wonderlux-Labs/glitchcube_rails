# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationMemory, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:session_id) }
    it { should validate_presence_of(:summary) }
    it { should validate_presence_of(:memory_type) }
    it { should validate_presence_of(:importance) }
    it { should validate_inclusion_of(:memory_type).in_array(%w[preference fact instruction context event]) }
    it { should validate_inclusion_of(:importance).in_range(1..10) }
  end

  describe 'scopes' do
    let!(:conversation1) { create(:conversation, session_id: 'session1') }
    let!(:conversation2) { create(:conversation, session_id: 'session2') }
    let!(:preference_memory) { create(:conversation_memory, conversation: conversation1, memory_type: 'preference', importance: 8) }
    let!(:fact_memory) { create(:conversation_memory, conversation: conversation2, memory_type: 'fact', importance: 5) }
    let!(:event_memory) { create(:conversation_memory, conversation: conversation1, memory_type: 'event', importance: 3) }

    describe '.by_session' do
      it 'returns memories for specific session' do
        expect(ConversationMemory.by_session('session1')).to contain_exactly(preference_memory, event_memory)
      end
    end

    describe '.by_type' do
      it 'returns memories of specific type' do
        expect(ConversationMemory.by_type('preference')).to contain_exactly(preference_memory)
      end
    end

    describe '.by_importance' do
      it 'returns memories with specific importance' do
        expect(ConversationMemory.by_importance(8)).to contain_exactly(preference_memory)
      end
    end

    describe '.high_importance' do
      it 'returns memories with importance 7-10' do
        expect(ConversationMemory.high_importance).to contain_exactly(preference_memory)
      end
    end

    describe '.medium_importance' do
      it 'returns memories with importance 4-6' do
        expect(ConversationMemory.medium_importance).to contain_exactly(fact_memory)
      end
    end

    describe '.low_importance' do
      it 'returns memories with importance 1-3' do
        expect(ConversationMemory.low_importance).to contain_exactly(event_memory)
      end
    end

    describe '.recent' do
      it 'orders by created_at desc' do
        expect(ConversationMemory.recent.first).to eq(event_memory)
      end
    end

    describe 'dynamic scopes' do
      it 'creates scopes for each memory type' do
        expect(ConversationMemory.preference).to contain_exactly(preference_memory)
        expect(ConversationMemory.fact).to contain_exactly(fact_memory)
        expect(ConversationMemory.event).to contain_exactly(event_memory)
      end
    end
  end

  describe '#metadata_json' do
    let(:memory) { build(:conversation_memory) }

    context 'with valid JSON' do
      before { memory.metadata = '{"tags": ["important"], "source": "user"}' }

      it 'parses JSON correctly' do
        expect(memory.metadata_json).to eq({
          'tags' => [ 'important' ],
          'source' => 'user'
        })
      end
    end

    context 'with invalid JSON' do
      before { memory.metadata = 'invalid json' }

      it 'returns empty hash' do
        expect(memory.metadata_json).to eq({})
      end
    end
  end

  describe '#metadata_json=' do
    let(:memory) { build(:conversation_memory) }

    it 'converts hash to JSON string' do
      memory.metadata_json = { tags: [ 'important' ], source: 'user' }
      expect(memory.metadata).to eq('{"tags":["important"],"source":"user"}')
    end
  end

  describe 'importance helper methods' do
    describe '#high_importance?' do
      it 'returns true for importance >= 7' do
        memory = build(:conversation_memory, importance: 7)
        expect(memory.high_importance?).to be(true)

        memory = build(:conversation_memory, importance: 10)
        expect(memory.high_importance?).to be(true)

        memory = build(:conversation_memory, importance: 6)
        expect(memory.high_importance?).to be(false)
      end
    end

    describe '#medium_importance?' do
      it 'returns true for importance 4-6' do
        memory = build(:conversation_memory, importance: 4)
        expect(memory.medium_importance?).to be(true)

        memory = build(:conversation_memory, importance: 6)
        expect(memory.medium_importance?).to be(true)

        memory = build(:conversation_memory, importance: 3)
        expect(memory.medium_importance?).to be(false)

        memory = build(:conversation_memory, importance: 7)
        expect(memory.medium_importance?).to be(false)
      end
    end

    describe '#low_importance?' do
      it 'returns true for importance <= 3' do
        memory = build(:conversation_memory, importance: 1)
        expect(memory.low_importance?).to be(true)

        memory = build(:conversation_memory, importance: 3)
        expect(memory.low_importance?).to be(true)

        memory = build(:conversation_memory, importance: 4)
        expect(memory.low_importance?).to be(false)
      end
    end
  end
end
