# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PersonaSwitchService, type: :service do
  describe '.handle_persona_switch' do
    let(:new_persona_id) { :sparkle }
    let(:previous_persona_id) { :buddy }

    context 'when there is a current goal' do
      let(:current_goal) do
        {
          goal_id: :make_friends,
          goal_description: "Have meaningful conversations and connect with fellow burners",
          category: "social_goals",
          started_at: 2.hours.ago,
          time_limit: 6.hours,
          time_remaining: 4.hours,
          expired: false
        }
      end

      before do
        allow(GoalService).to receive(:current_goal_status).and_return(current_goal)
        allow(LlmService).to receive(:call_with_tools).and_return({
          "choices" => [{"message" => {"content" => "I want to keep working on this goal!"}}]
        })
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:debug)
      end

      it 'calculates goal progress correctly' do
        expect(PersonaSwitchService).to receive(:notify_persona_with_goal).with(
          new_persona_id, current_goal, previous_persona_id
        )
        
        PersonaSwitchService.handle_persona_switch(new_persona_id, previous_persona_id)
      end

      it 'sends LLM message to new persona about existing goal' do
        expected_system_prompt = /You are Sparkle.*pure light consciousness/

        expect(LlmService).to receive(:call_with_tools) do |args|
          messages = args[:messages]
          expect(messages).to have(2).items
          expect(messages[0][:role]).to eq("system")
          expect(messages[0][:content]).to match(expected_system_prompt)
          expect(messages[1][:role]).to eq("user")
          expect(messages[1][:content]).to include("working on this goal")
          expect(messages[1][:content]).to include("33%") # 2 hours of 6 hours = 33%
          
          { "choices" => [{"message" => {"content" => "I'll keep going with this goal!"}}] }
        end

        PersonaSwitchService.handle_persona_switch(new_persona_id, previous_persona_id)
      end

      context 'when persona wants to change goal' do
        before do
          allow(LlmService).to receive(:call_with_tools).and_return({
            "choices" => [{"message" => {"content" => "I want something new and different! Let's roll the dice!"}}]
          })
        end

        it 'requests a new goal when persona indicates wanting change' do
          expect(GoalService).to receive(:request_new_goal).with(reason: "persona_sparkle_request")
          
          PersonaSwitchService.handle_persona_switch(new_persona_id, previous_persona_id)
        end
      end

      context 'when persona wants to keep goal' do
        before do
          allow(LlmService).to receive(:call_with_tools).and_return({
            "choices" => [{"message" => {"content" => "I'll keep working on this goal! Sounds fun!"}}]
          })
        end

        it 'does not request a new goal' do
          expect(GoalService).not_to receive(:request_new_goal)
          
          PersonaSwitchService.handle_persona_switch(new_persona_id, previous_persona_id)
        end
      end
    end

    context 'when there is no current goal' do
      before do
        allow(GoalService).to receive(:current_goal_status).and_return(nil)
        allow(GoalService).to receive(:select_goal).and_return({
          goal_id: :discover_art,
          goal_description: "Learn about new art installations and share what makes them special",
          category: "exploration_goals"
        })
        allow(Rails.logger).to receive(:info)
      end

      it 'selects a new goal automatically' do
        expect(GoalService).to receive(:select_goal)
        
        PersonaSwitchService.handle_persona_switch(new_persona_id, previous_persona_id)
      end

      it 'notifies persona about the new goal' do
        new_goal_status = {
          goal_description: "Learn about new art installations and share what makes them special",
          category: "exploration_goals",
          time_limit: 30.minutes
        }
        
        allow(GoalService).to receive(:current_goal_status).and_return(nil, new_goal_status)
        allow(LlmService).to receive(:call_with_tools).and_return({
          "choices" => [{"message" => {"content" => "Ooh! I love exploring art! ✨"}}]
        })

        expect(LlmService).to receive(:call_with_tools) do |args|
          messages = args[:messages]
          expect(messages[1][:content]).to include("selected a new one for you")
          expect(messages[1][:content]).to include("Learn about new art installations")
          
          { "choices" => [{"message" => {"content" => "Sounds great!"}}] }
        end

        PersonaSwitchService.handle_persona_switch(new_persona_id, previous_persona_id)
      end
    end
  end

  describe 'private methods' do
    describe '.calculate_goal_progress' do
      it 'calculates progress correctly for partial completion' do
        goal_status = {
          started_at: 3.hours.ago,
          time_limit: 6.hours
        }
        
        progress = PersonaSwitchService.send(:calculate_goal_progress, goal_status)
        expect(progress).to eq(50) # 3 of 6 hours = 50%
      end

      it 'caps progress at 100%' do
        goal_status = {
          started_at: 8.hours.ago,
          time_limit: 6.hours
        }
        
        progress = PersonaSwitchService.send(:calculate_goal_progress, goal_status)
        expect(progress).to eq(100)
      end

      it 'returns 0 for missing data' do
        progress = PersonaSwitchService.send(:calculate_goal_progress, {})
        expect(progress).to eq(0)
      end
    end

    describe '.wants_new_goal?' do
      it 'detects wanting change' do
        responses_wanting_change = [
          "I want something new and different!",
          "Let's roll the dice for a mysterious new goal!",
          "Throw this back and give me something else",
          "I'm not interested in continuing this"
        ]

        responses_wanting_change.each do |response|
          result = PersonaSwitchService.send(:wants_new_goal?, response)
          expect(result).to be(true), "Expected '#{response}' to indicate wanting change"
        end
      end

      it 'detects wanting to keep goal' do
        responses_wanting_to_keep = [
          "I'll keep working on this goal",
          "Let's continue with this, it sounds great!",
          "I want to stick with this one",
          "I'll maintain focus on this objective"
        ]

        responses_wanting_to_keep.each do |response|
          result = PersonaSwitchService.send(:wants_new_goal?, response)
          expect(result).to be(false), "Expected '#{response}' to indicate wanting to keep goal"
        end
      end
    end

    describe '.get_persona_instance' do
      it 'returns correct persona instances' do
        sparkle = PersonaSwitchService.send(:get_persona_instance, :sparkle)
        expect(sparkle).to be_a(Personas::SparklePersona)

        buddy = PersonaSwitchService.send(:get_persona_instance, :buddy)
        expect(buddy).to be_a(Personas::BuddyPersona)
      end

      it 'returns nil for unknown personas' do
        unknown = PersonaSwitchService.send(:get_persona_instance, :unknown)
        expect(unknown).to be_nil
      end
    end
  end
end