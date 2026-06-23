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
          "choices" => [ { "message" => { "content" => "Ooh! That sounds super fun! I'll keep working on making people happy! ✨" } } ]
        })
      end

      it "notifies the new persona about the existing goal" do
        expect(PersonaSwitchService).to receive(:handle_persona_switch).with(:sparkle, :buddy)

        CubePersona.set_current_persona(:sparkle)
      end

      # NOTE: PersonaSwitchService.handle_persona_switch was refactored — it no longer
      # auto-selects a goal (GoalService.select_goal) nor sends an LLM goal-context
      # notification (LlmService.call_with_tools). The specs covering that removed
      # goal-awareness flow ("includes goal context", "automatically selects a new goal",
      # "notifies the persona about the new goal") were deleted.
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
