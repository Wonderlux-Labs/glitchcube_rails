# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationLog, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:session_id) }
    it { should validate_presence_of(:user_message) }
    it { should validate_presence_of(:ai_response) }
  end

  describe 'scopes' do
    let!(:log1) { create(:conversation_log, session_id: 'session1') }
    let!(:log2) { create(:conversation_log, session_id: 'session2') }
    let!(:log3) { create(:conversation_log, session_id: 'session1') }

    describe '.by_session' do
      it 'returns logs for specific session' do
        expect(ConversationLog.by_session('session1')).to contain_exactly(log1, log3)
      end
    end

    describe '.recent' do
      it 'orders by created_at desc' do
        expect(ConversationLog.recent.first).to eq(log3)
      end
    end

    describe '.chronological' do
      it 'orders by created_at asc' do
        expect(ConversationLog.chronological.first).to eq(log1)
      end
    end
  end

  describe '#tool_results_json' do
    let(:log) { build(:conversation_log) }

    context 'with valid JSON' do
      before { log.tool_results = '{"success": true, "data": [1,2,3]}' }

      it 'parses JSON correctly' do
        expect(log.tool_results_json).to eq({ 'success' => true, 'data' => [ 1, 2, 3 ] })
      end
    end

    context 'with invalid JSON' do
      before { log.tool_results = 'invalid json' }

      it 'returns empty hash' do
        expect(log.tool_results_json).to eq({})
      end
    end

    context 'with blank tool_results' do
      before { log.tool_results = '' }

      it 'returns empty hash' do
        expect(log.tool_results_json).to eq({})
      end
    end
  end

  describe '#metadata_json' do
    let(:log) { build(:conversation_log) }

    context 'with valid JSON' do
      before { log.metadata = '{"user_id": 123, "source": "web"}' }

      it 'parses JSON correctly' do
        expect(log.metadata_json).to eq({ 'user_id' => 123, 'source' => 'web' })
      end
    end

    context 'with invalid JSON' do
      before { log.metadata = 'invalid json' }

      it 'returns empty hash' do
        expect(log.metadata_json).to eq({})
      end
    end
  end

  describe '#tool_results_json=' do
    let(:log) { build(:conversation_log) }

    it 'converts hash to JSON string' do
      log.tool_results_json = { success: true, data: [ 1, 2, 3 ] }
      expect(log.tool_results).to eq('{"success":true,"data":[1,2,3]}')
    end
  end

  describe '#metadata_json=' do
    let(:log) { build(:conversation_log) }

    it 'converts hash to JSON string' do
      log.metadata_json = { user_id: 123, source: 'web' }
      expect(log.metadata).to eq('{"user_id":123,"source":"web"}')
    end
  end
end
