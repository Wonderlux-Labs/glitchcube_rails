# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "CubePersona persona switching integration", type: :model do
  describe "persona switching" do
    before do
      # Mock Home Assistant service calls
      allow(HomeAssistantService).to receive(:entity).and_return({ "state" => "buddy" })
      allow(HomeAssistantService).to receive(:call_service)
      allow(Rails.cache).to receive(:write)
      allow(Rails.cache).to receive(:fetch).and_return("buddy")
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:debug)
    end

    context "when the persona changes" do
      it "hands off to PersonaSwitchService" do
        expect(PersonaSwitchService).to receive(:handle_persona_switch).with(:sparkle, :buddy)

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
