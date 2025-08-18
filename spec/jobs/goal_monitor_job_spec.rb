# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoalMonitorJob, type: :job do
  let(:job) { described_class.new }

  before do
    Rails.cache.clear
    allow(GoalService).to receive(:safety_mode_active?).and_return(false)
    allow(GoalService).to receive(:goal_expired?).and_return(false)
  end

  describe '#perform' do
    context 'in test environment' do
      it 'returns early without executing' do
        expect(Rails.logger).not_to receive(:info)
        expect { job.perform }.not_to raise_error
      end
    end

    context 'in production environment' do
      before do
        allow(Rails.env).to receive(:production?).and_return(true)
        allow(Rails.env).to receive(:development?).and_return(false)
      end

      it 'completes successfully' do
        expect(Rails.logger).to receive(:info).with('🎯 GoalMonitorJob starting')
        expect(Rails.logger).to receive(:info).with('✅ GoalMonitorJob completed successfully')

        expect { job.perform }.not_to raise_error
      end
    end

    context 'when an error occurs in production' do
      before do
        allow(Rails.env).to receive(:production?).and_return(true)
        allow(Rails.env).to receive(:development?).and_return(false)
        allow(job).to receive(:check_safety_conditions).and_raise(StandardError, 'Test error')
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with('❌ GoalMonitorJob failed: Test error')
        expect(Rails.logger).to receive(:error).with(kind_of(String)) # backtrace

        expect { job.perform }.not_to raise_error
      end
    end
  end

  describe '#check_safety_conditions' do
    let(:current_goal_status) do
      {
        goal_id: 'make_friends',
        goal_description: 'Have meaningful conversations',
        category: 'social_goals'
      }
    end

    context 'when safety mode becomes active with non-safety goal' do
      before do
        allow(GoalService).to receive(:safety_mode_active?).and_return(true)
        allow(GoalService).to receive(:current_goal_status).and_return(current_goal_status)
      end

      it 'switches to safety goal' do
        expect(Rails.logger).to receive(:info).with('⚠️ Safety mode active - switching to safety goal')
        expect(GoalService).to receive(:request_new_goal).with(reason: 'safety_mode_activated')

        job.send(:check_safety_conditions)
      end
    end

    context 'when safety mode deactivates with safety goal' do
      let(:safety_goal_status) do
        {
          goal_id: 'find_power',
          goal_description: 'Find nearest power source',
          category: 'safety_goals'
        }
      end

      before do
        allow(GoalService).to receive(:safety_mode_active?).and_return(false)
        allow(GoalService).to receive(:current_goal_status).and_return(safety_goal_status)
      end

      it 'switches to regular goal' do
        expect(Rails.logger).to receive(:info).with('✅ Safety mode deactivated - switching to regular goal')
        expect(GoalService).to receive(:request_new_goal).with(reason: 'safety_mode_deactivated')

        job.send(:check_safety_conditions)
      end
    end

    context 'when no goal is active' do
      before do
        allow(GoalService).to receive(:current_goal_status).and_return(nil)
      end

      it 'does not attempt to switch goals' do
        expect(GoalService).not_to receive(:request_new_goal)
        job.send(:check_safety_conditions)
      end
    end
  end

  describe '#check_goal_expiration' do
    context 'when goal is expired' do
      before do
        allow(GoalService).to receive(:goal_expired?).and_return(true)
      end

      it 'completes expired goal and selects new one' do
        expect(Rails.logger).to receive(:info).with('⏰ Goal expired - completing and selecting new goal')
        expect(GoalService).to receive(:complete_goal).with(completion_notes: 'Goal expired after time limit')
        expect(GoalService).to receive(:select_goal)

        job.send(:check_goal_expiration)
      end
    end

    context 'when goal is not expired' do
      before do
        allow(GoalService).to receive(:goal_expired?).and_return(false)
      end

      it 'does nothing' do
        expect(GoalService).not_to receive(:complete_goal)
        expect(GoalService).not_to receive(:select_goal)

        job.send(:check_goal_expiration)
      end
    end
  end

  describe '#check_for_goal_completion' do
    let!(:completion_log) do
      create(
        :conversation_log,
        ai_response: "Great! I helped three visitors find amazing art installations. Goal complete!",
        created_at: 5.minutes.ago
      )
    end

    let!(:normal_log) do
      create(
        :conversation_log,
        ai_response: "Just having a normal conversation here.",
        created_at: 3.minutes.ago
      )
    end

    let!(:old_completion_log) do
      create(
        :conversation_log,
        ai_response: "I completed my mission successfully!",
        created_at: 15.minutes.ago
      )
    end

    it 'detects goal completion from recent conversation logs' do
      expect(Rails.logger).to receive(:info).with('🎉 Detected goal completion in conversation - completing goal')
      expect(GoalService).to receive(:complete_goal).with(completion_notes: 'Persona indicated goal completion')
      expect(GoalService).to receive(:select_goal)

      job.send(:check_for_goal_completion)
    end

    it 'ignores old completion messages' do
      # Remove the recent completion log
      completion_log.destroy

      expect(GoalService).not_to receive(:complete_goal)
      expect(GoalService).not_to receive(:select_goal)

      job.send(:check_for_goal_completion)
    end

    context 'with various completion phrases' do
      let(:completion_phrases) do
        [
          "My goal is completed!",
          "I finished my goal successfully",
          "Goal done! Moving on to something else",
          "Mission accomplished, time for a new challenge",
          "Task complete, what's next?",
          "I did it! Success with my goal"
        ]
      end

      it 'detects various completion patterns' do
        completion_phrases.each do |phrase|
          log = create(:conversation_log, ai_response: phrase, created_at: 2.minutes.ago)

          expect(GoalService).to receive(:complete_goal).once
          expect(GoalService).to receive(:select_goal).once

          job.send(:check_for_goal_completion)

          log.destroy
        end
      end
    end

    context 'when no recent logs exist' do
      before do
        ConversationLog.destroy_all
      end

      it 'does nothing' do
        expect(GoalService).not_to receive(:complete_goal)
        expect(GoalService).not_to receive(:select_goal)

        job.send(:check_for_goal_completion)
      end
    end
  end
end
