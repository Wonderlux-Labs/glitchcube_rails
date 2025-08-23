# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Summary, type: :model do
  # Mock vectorsearch to prevent OpenAI API calls in unit tests
  before do
    allow_any_instance_of(Summary).to receive(:upsert_to_vectorsearch)
  end
  describe 'validations' do
    it { should validate_presence_of(:summary_text) }
    it { should validate_presence_of(:summary_type) }
    it { should validate_presence_of(:message_count) }
    it { should validate_inclusion_of(:summary_type).in_array(%w[hourly daily session topic goal_completion]) }
    it { should validate_numericality_of(:message_count).is_greater_than_or_equal_to(0) }
  end

  describe 'scopes' do
    let!(:hourly_summary) { create(:summary, summary_type: 'hourly', start_time: 2.hours.ago) }
    let!(:daily_summary) { create(:summary, summary_type: 'daily', start_time: 1.day.ago) }
    let!(:session_summary) { create(:summary, summary_type: 'session') }

    describe '.by_type' do
      it 'returns summaries of specific type' do
        expect(Summary.by_type('hourly')).to contain_exactly(hourly_summary)
        expect(Summary.by_type('daily')).to contain_exactly(daily_summary)
      end
    end

    describe '.recent' do
      it 'orders by created_at desc' do
        expect(Summary.recent.first).to eq(session_summary)
      end
    end

    describe '.chronological' do
      it 'orders by start_time asc' do
        expect(Summary.chronological.first).to eq(daily_summary)
      end
    end

    describe 'dynamic scopes' do
      it 'creates scopes for each summary type' do
        expect(Summary.hourly).to contain_exactly(hourly_summary)
        expect(Summary.daily).to contain_exactly(daily_summary)
        expect(Summary.session).to contain_exactly(session_summary)
      end
    end
  end

  describe '#metadata_json' do
    let(:summary) { build(:summary) }

    context 'with valid JSON' do
      before { summary.metadata = '{"conversations": 5, "participants": ["user1", "user2"]}' }

      it 'parses JSON correctly' do
        expect(summary.metadata_json).to eq({
          'conversations' => 5,
          'participants' => [ 'user1', 'user2' ]
        })
      end
    end

    context 'with invalid JSON' do
      before { summary.metadata = 'invalid json' }

      it 'returns empty hash' do
        expect(summary.metadata_json).to eq({})
      end
    end
  end

  describe '#metadata_json=' do
    let(:summary) { build(:summary) }

    it 'converts hash to JSON string' do
      summary.metadata_json = { conversations: 5, participants: [ 'user1', 'user2' ] }
      expect(summary.metadata).to eq('{"conversations":5,"participants":["user1","user2"]}')
    end
  end

  describe '#duration' do
    context 'with start_time and end_time' do
      let(:summary) { build(:summary, start_time: 2.hours.ago, end_time: 1.hour.ago) }

      it 'returns duration between start and end time' do
        expect(summary.duration).to be_within(1.second).of(1.hour)
      end
    end

    context 'without end_time' do
      let(:summary) { build(:summary, start_time: 2.hours.ago, end_time: nil) }

      it 'returns nil' do
        expect(summary.duration).to be_nil
      end
    end

    context 'without start_time' do
      let(:summary) { build(:summary, start_time: nil, end_time: 1.hour.ago) }

      it 'returns nil' do
        expect(summary.duration).to be_nil
      end
    end
  end

  describe '#duration_in_minutes' do
    context 'with duration' do
      let(:summary) { build(:summary, start_time: 2.hours.ago, end_time: 1.hour.ago) }

      it 'returns duration in minutes' do
        expect(summary.duration_in_minutes).to eq(60.0)
      end
    end

    context 'without duration' do
      let(:summary) { build(:summary, start_time: nil, end_time: nil) }

      it 'returns nil' do
        expect(summary.duration_in_minutes).to be_nil
      end
    end
  end

  describe 'goal completion functionality' do
    let!(:goal_summary1) { create(:summary, summary_type: 'goal_completion', summary_text: 'Completed goal: Make friends', metadata: { goal_id: 'make_friends', goal_category: 'social_goals', duration_seconds: 1800 }.to_json) }
    let!(:goal_summary2) { create(:summary, summary_type: 'goal_completion', summary_text: 'Completed goal: Find power', metadata: { goal_id: 'find_power', goal_category: 'safety_goals', duration_seconds: 600 }.to_json) }
    let!(:hourly_summary) { create(:summary, summary_type: 'hourly') }

    describe '.goal_completions' do
      it 'returns only goal completion summaries' do
        expect(Summary.goal_completions).to contain_exactly(goal_summary1, goal_summary2)
      end
    end

    describe '.completed_goals' do
      it 'returns formatted goal completion data' do
        completed = Summary.completed_goals

        expect(completed.length).to eq(2)

        first_goal = completed.find { |g| g[:goal_id] == 'make_friends' }
        expect(first_goal[:goal_category]).to eq('social_goals')
        expect(first_goal[:description]).to eq('Completed goal: Make friends')
        expect(first_goal[:duration]).to eq(1800)
      end
    end
  end
end
