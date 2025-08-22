# spec/services/prompt_service_spec.rb
require 'rails_helper'

RSpec.describe PromptService do
  let(:conversation) { create(:conversation) }
  let(:persona) { 'buddy' }
  let(:extra_context) { {} }

  describe '.build_prompt_for' do
    subject do
      described_class.build_prompt_for(
        persona: persona,
        conversation: conversation,
        extra_context: extra_context
      )
    end

    it 'returns a hash with expected keys' do
      expect(subject).to be_a(Hash)
      expect(subject).to have_key(:system_prompt)
      expect(subject).to have_key(:messages)
      expect(subject).to have_key(:tools)
      expect(subject).to have_key(:context)
    end

    context 'when structured output mode is active' do
      # Note: The code now always uses structured output mode with tool intentions
      # rather than having separate legacy/two-tier modes

      it 'includes structured output instructions with tool intentions' do
        expect(subject[:system_prompt]).to include('STRUCTURED OUTPUT WITH TOOL INTENTIONS:')
        expect(subject[:system_prompt]).to include('Tool intentions should be natural language')
        expect(subject[:system_prompt]).to include('AVAILABLE TOOL CATEGORIES:')
        expect(subject[:system_prompt]).not_to include('AVAILABLE TOOLS:')
      end

      it 'includes real tool categories from registry' do
        expect(subject[:system_prompt]).to include('AVAILABLE TOOL CATEGORIES:')
        # Should include actual tool categories from our real tools
        expect(subject[:system_prompt]).to include('lights')
      end

      it 'returns tool definitions for backend execution' do
        tools = subject[:tools]
        expect(tools).to be_an(Array)
        expect(tools).not_to be_empty
        expect(tools.first).to respond_to(:name)
      end
    end
  end

  describe '#build_structured_output_instructions' do
    let(:service) { described_class.new(persona: persona, conversation: conversation, extra_context: extra_context) }

    subject { service.send(:build_structured_output_instructions) }

    it 'includes structured output explanation' do
      expect(subject).to include('STRUCTURED OUTPUT WITH TOOL INTENTIONS')
      expect(subject).to include('Instead of calling tools directly')
    end

    it 'lists actual available tool categories' do
      expect(subject).to include('AVAILABLE TOOL CATEGORIES:')
      # Should include real categories from our actual tool registry
      expect(subject).to include('lights')
    end

    it 'provides example tool intentions' do
      expect(subject).to include('Make lights golden and warm')
      expect(subject).to include('Play something energetic')
    end

    it 'explains the background execution' do
      expect(subject).to include('Home Assistant\'s conversation agent will execute')
    end
  end

  describe '#enhance_prompt_with_context' do
    let(:service) { described_class.new(persona: persona, conversation: conversation, extra_context: extra_context) }
    let(:base_prompt) { "You are a test character." }

    before do
      allow(service).to receive(:load_base_system_prompt).and_return("Base system rules")
      allow(service).to receive(:build_current_context).and_return("Current context")
      allow(service).to receive(:build_structured_output_instructions).and_return("Structured instructions")
    end

    it 'includes structured output instructions' do
      result = service.send(:enhance_prompt_with_context, base_prompt)
      expect(result).to include("STRUCTURED OUTPUT WITH TOOL INTENTIONS:")
      expect(result).to include("Structured instructions")
      expect(result).to include("CURRENT CONTEXT:")
      expect(result).to include("Current context")
    end

    it 'combines all prompt components in correct order' do
      result = service.send(:enhance_prompt_with_context, base_prompt)

      # Check order
      expect(result).to match(/You are a test character.*Base system rules.*STRUCTURED OUTPUT.*CURRENT CONTEXT/m)
    end
  end

  describe '#build_goal_context' do
    let(:service) { described_class.new(persona: persona, conversation: conversation, extra_context: extra_context) }

    context 'when goal exists' do
      let(:goal_status) do
        {
          goal_id: 'make_friends',
          goal_description: 'Have meaningful conversations with visitors',
          category: 'social_goals',
          started_at: 10.minutes.ago,
          time_remaining: 1200, # 20 minutes in seconds
          expired: false
        }
      end

      before do
        allow(GoalService).to receive(:current_goal_status).and_return(goal_status)
        allow(service).to receive(:safety_mode).and_return("")
        allow(Summary).to receive(:goal_completions).and_return(double(limit: []))
      end

      it 'includes goal description and formatted time remaining' do
        context = service.send(:build_goal_context)

        expect(context).to include('Current Goal: Have meaningful conversations with visitors')
        expect(context).to include('Time remaining: 20m')
      end
    end

    context 'when safety mode is active' do
      let(:goal_status) do
        {
          goal_id: 'find_power',
          goal_description: 'Find nearest power source',
          category: 'safety_goals',
          started_at: 5.minutes.ago,
          time_remaining: 1500, # 25 minutes in seconds
          expired: false
        }
      end

      before do
        allow(GoalService).to receive(:current_goal_status).and_return(goal_status)
        allow(service).to receive(:safety_mode).and_return("YOU ARE IN SAFETY MODE! YOU MUST FIND SHELTER AND GET SOME POWER")
        allow(Summary).to receive(:goal_completions).and_return(double(limit: []))
      end

      it 'includes safety mode warning when active' do
        context = service.send(:build_goal_context)

        expect(context).to include('YOU ARE IN SAFETY MODE!')
        expect(context).to include('Current Goal: Find nearest power source')
      end
    end

    context 'when goal is expired' do
      let(:goal_status) do
        {
          goal_id: 'make_friends',
          goal_description: 'Have meaningful conversations',
          category: 'social_goals',
          started_at: 40.minutes.ago,
          time_remaining: 0,
          expired: true
        }
      end

      before do
        allow(GoalService).to receive(:current_goal_status).and_return(goal_status)
        allow(service).to receive(:safety_mode).and_return("")
        allow(Summary).to receive(:goal_completions).and_return(double(limit: []))
      end

      it 'shows goal expiration warning with correct formatting' do
        context = service.send(:build_goal_context)

        expect(context).to include('⏰ Goal has expired - consider completing or switching goals')
      end
    end

    context 'when recent goal completions exist' do
      let(:goal_status) do
        {
          goal_id: 'spread_joy',
          goal_description: 'Make people laugh',
          category: 'social_goals',
          started_at: 5.minutes.ago,
          time_remaining: 1500, # 25 minutes in seconds
          expired: false
        }
      end

      let(:mock_completions) do
        [
          instance_double(Summary, summary_text: 'Completed goal: Made 5 people smile'),
          instance_double(Summary, summary_text: 'Completed goal: Helped visitor find camp')
        ]
      end

      before do
        allow(GoalService).to receive(:current_goal_status).and_return(goal_status)
        allow(service).to receive(:safety_mode).and_return("")
        allow(Summary).to receive(:goal_completions).and_return(double(limit: mock_completions))
      end

      it 'includes recent completions' do
        context = service.send(:build_goal_context)

        expect(context).to include('Recent completions: Completed goal: Made 5 people smile, Completed goal: Helped visitor find camp')
      end
    end

    context 'when no goal exists' do
      before do
        allow(GoalService).to receive(:current_goal_status).and_return(nil)
      end

      it 'returns nil' do
        expect(service.send(:build_goal_context)).to be_nil
      end
    end

    context 'when goal service raises an error' do
      before do
        allow(GoalService).to receive(:current_goal_status).and_raise(StandardError, 'Goal service error')
        allow(Rails.logger).to receive(:error)
      end

      it 'logs error and returns nil' do
        expect(Rails.logger).to receive(:error).with(/Failed to build goal context/)
        expect(service.send(:build_goal_context)).to be_nil
      end
    end
  end

  describe '#format_time_duration' do
    let(:service) { described_class.new(persona: persona, conversation: conversation, extra_context: extra_context) }

    it 'formats seconds correctly' do
      expect(service.send(:format_time_duration, 45)).to eq('45s')
    end

    it 'formats minutes correctly' do
      expect(service.send(:format_time_duration, 90)).to eq('1m')
      expect(service.send(:format_time_duration, 300)).to eq('5m')
    end

    it 'formats hours and minutes correctly' do
      expect(service.send(:format_time_duration, 3661)).to eq('1h 1m')
      expect(service.send(:format_time_duration, 7200)).to eq('2h 0m')
    end
  end
end
