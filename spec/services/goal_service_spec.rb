# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoalService, type: :service do
  let(:mock_ha_service) { instance_double(HomeAssistantService) }
  let(:goals_yaml) do
    {
      'safety_goals' => {
        'find_power' => {
          'description' => 'Find nearest power source',
          'triggers' => ['battery_low', 'battery_critical']
        },
        'seek_help' => {
          'description' => 'Seek assistance',
          'triggers' => ['safety_mode']
        }
      },
      'social_goals' => {
        'make_friends' => {
          'description' => 'Have meaningful conversations'
        },
        'spread_joy' => {
          'description' => 'Make people laugh'
        }
      }
    }
  end

  before do
    allow(HomeAssistantService).to receive(:new).and_return(mock_ha_service)
    allow(YAML).to receive(:load_file).and_return(goals_yaml)
    allow(File).to receive(:exist?).with(Rails.root.join('data', 'goals.yml')).and_return(true)
    Rails.cache.clear
  end

  describe '.load_goals' do
    it 'loads goals from YAML file' do
      expect(described_class.load_goals).to eq(goals_yaml)
    end

    it 'returns empty hash if file does not exist' do
      allow(File).to receive(:exist?).and_return(false)
      expect(described_class.load_goals).to eq({})
    end

    it 'returns empty hash and logs error if YAML parsing fails' do
      allow(YAML).to receive(:load_file).and_raise(StandardError, 'Parse error')
      expect(Rails.logger).to receive(:error).with(/Failed to load goals/)
      
      expect(described_class.load_goals).to eq({})
    end
  end

  describe '.select_goal' do
    context 'when safety mode is active' do
      before do
        allow(described_class).to receive(:safety_mode_active?).and_return(true)
      end

      it 'selects a safety goal' do
        goal = described_class.select_goal
        
        expect(goal[:category]).to eq('safety_goals')
        expect(['find_power', 'seek_help']).to include(goal[:id])
      end

      it 'stores goal state in cache' do
        goal = described_class.select_goal(time_limit: 15.minutes)
        
        expect(Rails.cache.read('current_goal')).to eq(goal)
        expect(Rails.cache.read('current_goal_started_at')).to be_within(1.second).of(Time.current)
        expect(Rails.cache.read('current_goal_max_time_limit')).to eq(15.minutes)
      end
    end

    context 'when safety mode is not active' do
      before do
        allow(described_class).to receive(:safety_mode_active?).and_return(false)
      end

      it 'selects a non-safety goal' do
        goal = described_class.select_goal
        
        expect(goal[:category]).to eq('social_goals')
        expect(['make_friends', 'spread_joy']).to include(goal[:id])
      end
    end

    it 'returns nil if no goals available' do
      allow(described_class).to receive(:load_goals).and_return({})
      expect(described_class.select_goal).to be_nil
    end
  end

  describe '.current_goal_status' do
    let(:goal) do
      {
        id: 'make_friends',
        description: 'Have meaningful conversations',
        category: 'social_goals'
      }
    end

    context 'when goal exists' do
      before do
        Rails.cache.write('current_goal', goal)
        Rails.cache.write('current_goal_started_at', 10.minutes.ago)
        Rails.cache.write('current_goal_max_time_limit', 30.minutes)
      end

      it 'returns goal status' do
        status = described_class.current_goal_status
        
        expect(status[:goal_id]).to eq('make_friends')
        expect(status[:goal_description]).to eq('Have meaningful conversations')
        expect(status[:category]).to eq('social_goals')
        expect(status[:time_remaining]).to be_within(60).of(20.minutes)
        expect(status[:expired]).to be false
      end
    end

    context 'when goal is expired' do
      before do
        Rails.cache.write('current_goal', goal)
        Rails.cache.write('current_goal_started_at', 35.minutes.ago)
        Rails.cache.write('current_goal_max_time_limit', 30.minutes)
      end

      it 'marks goal as expired' do
        status = described_class.current_goal_status
        expect(status[:expired]).to be true
      end
    end

    it 'returns nil when no goal exists' do
      expect(described_class.current_goal_status).to be_nil
    end
  end

  describe '.goal_expired?' do
    it 'returns false when no goal exists' do
      expect(described_class.goal_expired?).to be false
    end

    it 'returns false when goal is not expired' do
      Rails.cache.write('current_goal_started_at', 10.minutes.ago)
      Rails.cache.write('current_goal_max_time_limit', 30.minutes)
      
      expect(described_class.goal_expired?).to be false
    end

    it 'returns true when goal is expired' do
      Rails.cache.write('current_goal_started_at', 35.minutes.ago)
      Rails.cache.write('current_goal_max_time_limit', 30.minutes)
      
      expect(described_class.goal_expired?).to be true
    end
  end

  describe '.complete_goal' do
    let(:goal) do
      {
        id: 'make_friends',
        description: 'Have meaningful conversations',
        category: 'social_goals'
      }
    end

    before do
      Rails.cache.write('current_goal', goal)
      Rails.cache.write('current_goal_started_at', 10.minutes.ago)
      Rails.cache.write('current_goal_max_time_limit', 30.minutes)
    end

    it 'creates a goal completion summary' do
      expect {
        described_class.complete_goal(completion_notes: 'Great conversations!')
      }.to change { Summary.count }.by(1)

      summary = Summary.last
      expect(summary.summary_type).to eq('goal_completion')
      expect(summary.summary_text).to eq('Completed goal: Have meaningful conversations')
      
      metadata = summary.metadata_json
      expect(metadata['goal_id']).to eq('make_friends')
      expect(metadata['goal_category']).to eq('social_goals')
      expect(metadata['completion_notes']).to eq('Great conversations!')
    end

    it 'clears goal from cache' do
      described_class.complete_goal
      
      expect(Rails.cache.read('current_goal')).to be_nil
      expect(Rails.cache.read('current_goal_started_at')).to be_nil
      expect(Rails.cache.read('current_goal_max_time_limit')).to be_nil
    end

    it 'returns false when no current goal' do
      Rails.cache.clear
      expect(described_class.complete_goal).to be false
    end
  end

  describe '.all_completed_goals' do
    let!(:goal_summary1) { create(:summary, summary_type: 'goal_completion', summary_text: 'Completed goal: Make friends') }
    let!(:goal_summary2) { create(:summary, summary_type: 'goal_completion', summary_text: 'Completed goal: Spread joy') }
    let!(:hourly_summary) { create(:summary, summary_type: 'hourly') }

    it 'returns only goal completion summaries' do
      completions = described_class.all_completed_goals
      
      expect(completions.length).to eq(2)
      expect(completions.map { |c| c[:description] }).to contain_exactly(
        'Completed goal: Make friends',
        'Completed goal: Spread joy'
      )
    end
  end

  describe '.safety_mode_active?' do
    context 'when Home Assistant safety mode is on' do
      before do
        allow(mock_ha_service).to receive(:entity)
          .with('input_boolean.safety_mode')
          .and_return({ 'state' => 'on' })
        allow(mock_ha_service).to receive(:entity)
          .with('input_select.battery_level')
          .and_return({ 'state' => 'excellent' })
      end

      it 'returns true' do
        expect(described_class.safety_mode_active?).to be true
      end
    end

    context 'when battery level is critical' do
      before do
        allow(mock_ha_service).to receive(:entity)
          .with('input_boolean.safety_mode')
          .and_return({ 'state' => 'off' })
        allow(mock_ha_service).to receive(:entity)
          .with('input_select.battery_level')
          .and_return({ 'state' => 'critical' })
      end

      it 'returns true' do
        expect(described_class.safety_mode_active?).to be true
      end
    end

    context 'when both safety mode is off and battery is good' do
      before do
        allow(mock_ha_service).to receive(:entity)
          .with('input_boolean.safety_mode')
          .and_return({ 'state' => 'off' })
        allow(mock_ha_service).to receive(:entity)
          .with('input_select.battery_level')
          .and_return({ 'state' => 'excellent' })
      end

      it 'returns false' do
        expect(described_class.safety_mode_active?).to be false
      end
    end

    it 'returns false on Home Assistant error' do
      allow(mock_ha_service).to receive(:entity).and_raise(StandardError, 'HA error')
      expect(Rails.logger).to receive(:error).with(/Failed to check safety mode/)
      
      expect(described_class.safety_mode_active?).to be false
    end
  end

  describe '.battery_level_critical?' do
    it 'returns true for critical battery' do
      allow(mock_ha_service).to receive(:entity)
        .with('input_select.battery_level')
        .and_return({ 'state' => 'critical' })
      
      expect(described_class.battery_level_critical?).to be true
    end

    it 'returns true for low battery' do
      allow(mock_ha_service).to receive(:entity)
        .with('input_select.battery_level')
        .and_return({ 'state' => 'low' })
      
      expect(described_class.battery_level_critical?).to be true
    end

    it 'returns false for good battery' do
      allow(mock_ha_service).to receive(:entity)
        .with('input_select.battery_level')
        .and_return({ 'state' => 'excellent' })
      
      expect(described_class.battery_level_critical?).to be false
    end
  end

  describe '.request_new_goal' do
    let(:current_goal) do
      {
        id: 'make_friends',
        description: 'Have meaningful conversations',
        category: 'social_goals'
      }
    end

    before do
      Rails.cache.write('current_goal', current_goal)
      Rails.cache.write('current_goal_started_at', 5.minutes.ago)
      Rails.cache.write('current_goal_max_time_limit', 30.minutes)
      allow(described_class).to receive(:safety_mode_active?).and_return(false)
    end

    it 'completes current goal and selects new one' do
      expect(described_class).to receive(:complete_goal)
        .with(completion_notes: 'Switched due to: persona_request')
      expect(described_class).to receive(:select_goal).with(time_limit: 30.minutes)
      
      described_class.request_new_goal(reason: 'persona_request')
    end
  end
end