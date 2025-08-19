# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "CubePersona persona switching integration", type: :model do
  describe "persona switching with goal awareness" do
    before do
      # Mock Home Assistant service calls
      allow(HomeAssistantService).to receive(:entity).and_return({ "state" => "buddy" })
      allow(HomeAssistantService).to receive(:call_service)
      allow(Rails.cache).to receive(:write)
      allow(Rails.cache).to receive(:fetch).and_return("buddy")
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:debug)
    end

    context "when switching personas with an active goal" do
      let(:active_goal) do
        {
          goal_id: :spread_joy,
          goal_description: "Make people laugh and feel the magic of Burning Man",
          category: "social_goals",
          started_at: 1.hour.ago,
          time_limit: 4.hours,
          time_remaining: 3.hours,
          expired: false
        }
      end

      before do
        allow(GoalService).to receive(:current_goal_status).and_return(active_goal)
        allow(LlmService).to receive(:call_with_tools).and_return({
          "choices" => [{"message" => {"content" => "Ooh! That sounds super fun! I'll keep working on making people happy! ✨"}}]
        })
      end

      it "notifies the new persona about the existing goal" do
        expect(PersonaSwitchService).to receive(:handle_persona_switch).with(:sparkle, :buddy)
        
        CubePersona.set_current_persona(:sparkle)
      end

      it "includes goal context in the persona notification" do
        expect(LlmService).to receive(:call_with_tools) do |args|
          messages = args[:messages]
          user_message = messages[1][:content]
          
          expect(user_message).to include("Make people laugh and feel the magic")
          expect(user_message).to include("25%") # 1 hour of 4 hours
          expect(user_message).to include("Buddy was working on this goal")
          
          { "choices" => [{"message" => {"content" => "I'll continue this joyful mission!"}}] }
        end

        CubePersona.set_current_persona(:sparkle)
      end
    end

    context "when switching personas with no active goal" do
      let(:new_goal_status) do
        {
          goal_description: "Learn about new art installations",
          category: "exploration_goals",
          time_limit: 30.minutes
        }
      end

      before do
        # First call returns nil (no current goal), second call returns new goal after selection
        allow(GoalService).to receive(:current_goal_status).and_return(nil, new_goal_status)
        allow(GoalService).to receive(:select_goal).and_return({
          goal_id: :discover_art,
          goal_description: "Learn about new art installations",
          category: "exploration_goals"
        })
        allow(LlmService).to receive(:call_with_tools).and_return({
          "choices" => [{"message" => {"content" => "Ooh! Art exploration sounds amazing! ✨"}}]
        })
      end

      it "automatically selects a new goal" do
        expect(GoalService).to receive(:select_goal)
        
        CubePersona.set_current_persona(:sparkle)
      end

      it "notifies the persona about the new goal" do
        expect(LlmService).to receive(:call_with_tools) do |args|
          messages = args[:messages]
          user_message = messages[1][:content]
          
          expect(user_message).to include("selected a new one for you")
          expect(user_message).to include("Learn about new art installations")
          
          { "choices" => [{"message" => {"content" => "Perfect! I love art!"}}] }
        end

        CubePersona.set_current_persona(:sparkle)
      end
    end

    context "when persona doesn't actually change" do
      it "doesn't trigger persona switching logic" do
        allow(CubePersona).to receive(:current_persona).and_return(:sparkle)
        expect(PersonaSwitchService).not_to receive(:handle_persona_switch)
        
        CubePersona.set_current_persona(:sparkle)
      end
    end
  end
end