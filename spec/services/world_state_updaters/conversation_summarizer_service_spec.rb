# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WorldStateUpdaters::ConversationSummarizerService, type: :service do
  let(:conversation_ids) { [ conversation.id ] }
  let(:conversation) { create(:conversation, session_id: 'test_session', started_at: 1.hour.ago, ended_at: 30.minutes.ago) }
  let(:service) { described_class.new(conversation_ids) }

  before do
    allow(LlmService).to receive(:generate_text).and_return(
      '{"general_mood": "helpful", "important_questions": ["How can I help?"], "useful_thoughts": ["User needs guidance"], "goal_progress": "good_progress", "general_summary": "Productive conversation"}'
    )
  end

  describe '#call' do
    context 'with valid conversations' do
      let!(:conversation_log1) do
        create(:conversation_log,
          session_id: conversation.session_id,
          user_message: 'Can you help me find art installations?',
          ai_response: 'I\'d love to help! Let me guide you to some amazing installations.',
          created_at: 45.minutes.ago
        )
      end

      let!(:conversation_log2) do
        create(:conversation_log,
          session_id: conversation.session_id,
          user_message: 'That was great, thanks!',
          ai_response: 'You\'re welcome! I\'m making good progress on my goal to help visitors.',
          created_at: 35.minutes.ago
        )
      end

      it 'creates an hourly summary record' do
        expect { service.call }.to change { Summary.count }.by(1)

        summary = Summary.last
        expect(summary.summary_type).to eq('hourly')
        expect(summary.summary_text).to eq('Productive conversation')
        expect(summary.start_time).to be_within(1.minute).of(conversation.started_at)
        expect(summary.end_time).to be_within(1.minute).of(conversation.ended_at)
        expect(summary.message_count).to eq(2)
      end

      it 'stores goal progress in metadata' do
        summary = service.call

        metadata = summary.metadata_json
        expect(metadata['general_mood']).to eq('helpful')
        expect(metadata['important_questions']).to eq([ 'How can I help?' ])
        expect(metadata['useful_thoughts']).to eq([ 'User needs guidance' ])
        expect(metadata['goal_progress']).to eq('good_progress')
        expect(metadata['conversation_ids']).to eq(conversation_ids)
      end

      it 'includes goal context in LLM prompt' do
        goal_status = {
          goal_description: 'Help visitors find amazing art',
          category: 'utility_goals',
          time_remaining: 15.minutes
        }

        allow(GoalService).to receive(:current_goal_status).and_return(goal_status)
        allow(GoalService).to receive(:safety_mode_active?).and_return(false)

        expect(LlmService).to receive(:generate_text) do |args|
          expect(args[:prompt]).to include('Current Goal Context:')
          expect(args[:prompt]).to include('Active Goal: Help visitors find amazing art')
          expect(args[:prompt]).to include('Goal Category: utility_goals')
          '{"general_mood": "helpful", "important_questions": [], "useful_thoughts": [], "goal_progress": "completed", "general_summary": "Goal achieved"}'
        end

        service.call
      end
    end

    context 'with no conversations' do
      let(:conversation_ids) { [] }

      it 'creates empty summary' do
        summary = service.call

        expect(summary.summary_type).to eq('hourly')
        expect(summary.summary_text).to eq('No conversations found in this time period.')
        expect(summary.message_count).to eq(0)

        metadata = summary.metadata_json
        expect(metadata['goal_progress']).to eq('no_progress')
      end
    end

    context 'when LLM call fails' do
      before do
        allow(LlmService).to receive(:generate_text).and_raise(StandardError, 'LLM error')
        allow(Rails.logger).to receive(:error)
      end

      it 'returns empty summary when LLM fails' do
        result = service.call

        expect(result.summary_text).to include('No conversations found')
        metadata = result.metadata_json
        expect(metadata['goal_progress']).to eq('no_progress')
      end
    end
  end

  describe '#build_goal_context_for_prompt' do
    context 'with active goal' do
      let(:goal_status) do
        {
          goal_description: 'Make meaningful connections with visitors',
          category: 'social_goals',
          time_remaining: 25.minutes
        }
      end

      before do
        allow(GoalService).to receive(:current_goal_status).and_return(goal_status)
        allow(GoalService).to receive(:safety_mode_active?).and_return(false)
      end

      it 'builds goal context string' do
        context = service.send(:build_goal_context_for_prompt)

        expect(context).to include('Active Goal: Make meaningful connections with visitors')
        expect(context).to include('Goal Category: social_goals')
        expect(context).to include('Time Remaining: 25 minutes')
      end
    end

    context 'with safety mode active' do
      let(:goal_status) do
        {
          goal_description: 'Find nearest charging station',
          category: 'safety_goals',
          time_remaining: 10.minutes
        }
      end

      before do
        allow(GoalService).to receive(:current_goal_status).and_return(goal_status)
        allow(GoalService).to receive(:safety_mode_active?).and_return(true)
      end

      it 'includes safety mode indicator' do
        context = service.send(:build_goal_context_for_prompt)

        expect(context).to include('SAFETY MODE ACTIVE')
        expect(context).to include('Active Goal: Find nearest charging station')
      end
    end

    context 'with expired goal' do
      let(:goal_status) do
        {
          goal_description: 'Share weather updates',
          category: 'utility_goals',
          time_remaining: 0,
          expired: true
        }
      end

      before do
        allow(GoalService).to receive(:current_goal_status).and_return(goal_status)
        allow(GoalService).to receive(:safety_mode_active?).and_return(false)
      end

      it 'shows expired status' do
        context = service.send(:build_goal_context_for_prompt)

        expect(context).to include('Goal Status: EXPIRED')
      end
    end

    context 'with no active goal' do
      before do
        allow(GoalService).to receive(:current_goal_status).and_return(nil)
      end

      it 'returns no active goal message' do
        context = service.send(:build_goal_context_for_prompt)
        expect(context).to eq('No active goal')
      end
    end

    context 'when goal service fails' do
      before do
        allow(GoalService).to receive(:current_goal_status).and_raise(StandardError, 'Goal service error')
        allow(Rails.logger).to receive(:error)
      end

      it 'logs error and returns fallback message' do
        expect(Rails.logger).to receive(:error).with(/Failed to build goal context for prompt/)

        context = service.send(:build_goal_context_for_prompt)
        expect(context).to eq('Goal context unavailable')
      end
    end
  end

  describe '#build_system_prompt' do
    it 'includes goal progress in system prompt' do
      prompt = service.send(:build_system_prompt)

      expect(prompt).to include('goal_progress')
      expect(prompt).to include('Did the persona make progress toward or complete their current goal?')
      expect(prompt).to include('(completed, good_progress, some_progress, no_progress, goal_changed)')
    end

    it 'includes goal progress in example JSON' do
      prompt = service.send(:build_system_prompt)

      expect(prompt).to include('"goal_progress": "good_progress"')
    end
  end

  describe 'goal progress evaluation' do
    let!(:conversation_log) do
      create(:conversation_log,
        session_id: conversation.session_id,
        user_message: 'How are you doing with your goals?',
        ai_response: 'I successfully helped 3 visitors find art installations! My goal is now complete.',
        created_at: 30.minutes.ago
      )
    end

    context 'when LLM detects goal completion' do
      before do
        allow(LlmService).to receive(:generate_text).and_return(
          '{"general_mood": "accomplished", "important_questions": [], "useful_thoughts": ["Successfully completed assistance goal"], "goal_progress": "completed", "general_summary": "Goal completion achieved"}'
        )
      end

      it 'captures goal completion in summary' do
        summary = service.call

        metadata = summary.metadata_json
        expect(metadata['goal_progress']).to eq('completed')
        expect(metadata['useful_thoughts']).to include('Successfully completed assistance goal')
      end
    end

    context 'when LLM detects partial progress' do
      before do
        allow(LlmService).to receive(:generate_text).and_return(
          '{"general_mood": "determined", "important_questions": ["What installations should I recommend next?"], "useful_thoughts": ["Making steady progress helping visitors"], "goal_progress": "some_progress", "general_summary": "Steady progress toward goals"}'
        )
      end

      it 'captures partial progress in summary' do
        summary = service.call

        metadata = summary.metadata_json
        expect(metadata['goal_progress']).to eq('some_progress')
        expect(metadata['useful_thoughts']).to include('Making steady progress helping visitors')
      end
    end

    context 'when goal changes during conversation' do
      before do
        allow(LlmService).to receive(:generate_text).and_return(
          '{"general_mood": "adaptive", "important_questions": [], "useful_thoughts": ["Switched from art guidance to safety assistance"], "goal_progress": "goal_changed", "general_summary": "Goal pivot during interaction"}'
        )
      end

      it 'captures goal change in summary' do
        summary = service.call

        metadata = summary.metadata_json
        expect(metadata['goal_progress']).to eq('goal_changed')
        expect(metadata['useful_thoughts']).to include('Switched from art guidance to safety assistance')
      end
    end
  end

  describe 'error handling' do
    context 'when conversation data gathering fails' do
      before do
        allow(service).to receive(:gather_conversation_data).and_raise(StandardError, 'Database error')
        allow(Rails.logger).to receive(:error)
      end

      it 'raises service error with context' do
        expect { service.call }.to raise_error(described_class::Error, /Failed to generate conversation summary: Database error/)
      end
    end

    context 'when JSON parsing fails' do
      before do
        allow(LlmService).to receive(:generate_text).and_return('invalid json response')
        allow(Rails.logger).to receive(:error)
      end

      it 'uses fallback parsing without goal_progress' do
        summary = service.call

        metadata = summary.metadata_json
        expect(metadata['goal_progress']).to be_nil # Fallback doesn't include goal_progress
        expect(metadata['general_mood']).to eq('unable to determine')
        expect(metadata['useful_thoughts']).to include('Failed to parse AI response')
        expect(summary.summary_text).to include('invalid json response')
      end
    end
  end
end
