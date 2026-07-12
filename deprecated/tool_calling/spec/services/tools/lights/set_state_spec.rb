# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::Lights::SetState, type: :service do
  include ToolTestHelpers

  before do
    mock_entities
    mock_service_call({})
  end

  describe "#call" do
    context "with symbol keys (normal Ruby)" do
      it "executes successfully" do
        result = described_class.call(
          entity_id: "light.cube_inner",
          state: "on",
          brightness: 75
        )

        expect(result[:success]).to be_truthy
        expect(result[:entity_id]).to eq("light.cube_inner")
      end
    end

    context "with RGB color as string" do
      it "converts string RGB to array internally" do
        result = described_class.call(
          entity_id: "light.cube_inner",
          state: "on",
          rgb_color: "255,128,0"
        )

        expect(result[:success]).to be_truthy
        expect(result[:rgb_color]).to eq([ 255, 128, 0 ])
      end

      it "handles RGB with spaces" do
        result = described_class.call(
          entity_id: "light.cube_inner",
          state: "on",
          rgb_color: "255, 128, 0"
        )

        expect(result[:success]).to be_truthy
        expect(result[:rgb_color]).to eq([ 255, 128, 0 ])
      end

      it "rejects invalid RGB format" do
        result = described_class.call(
          entity_id: "light.cube_inner",
          state: "on",
          rgb_color: "255,128"
        )

        expect(result[:success]).to be_falsy
        expect(result[:error]).to include("Invalid rgb_color format")
      end
    end

    context "with string keys (from JSON)" do
      it "handles string keys via Tools::Registry.execute_tool" do
        result = Tools::Registry.execute_tool('set_light_state',
          "entity_id" => "light.cube_inner",
          "state" => "on",
          "rgb_color" => "255,0,0"
        )

        expect(result).to be_a(Hash)
        expect(result[:success]).to be_truthy
        # Should not fail with missing keywords error
        expect(result[:error]).to be_nil
      end

      it "handles string keys via AsyncToolJob" do
        job_result = AsyncToolJob.perform_now(
          'set_light_state',
          {
            "entity_id" => "light.cube_inner",
            "state" => "on",
            "rgb_color" => "255,0,0"
          },
          'test_session',
          'test_conversation'
        )

        expect(job_result).to be_a(Hash)
        expect(job_result[:success]).to be_truthy
        # Should not fail with missing keywords error
        expect(job_result[:error]).to be_nil
      end
    end

    context "with blank parameters" do
      it "filters out blank strings" do
        result = Tools::Registry.execute_tool('set_light_state',
          "entity_id" => "light.cube_inner",
          "state" => "on",
          "effect" => "",  # blank string should be filtered
          "rgb_color" => "255,0,0"
        )

        expect(result[:success]).to be_truthy
        # Tool should not receive the blank effect parameter
      end

      it "filters out nil values" do
        result = Tools::Registry.execute_tool('set_light_state',
          "entity_id" => "light.cube_inner",
          "state" => "on",
          "effect" => nil,  # nil should be filtered
          "rgb_color" => "255,0,0"
        )

        expect(result[:success]).to be_truthy
      end
    end

    context "with missing required parameters" do
      it "requires entity_id" do
        expect {
          described_class.call(state: "on")
        }.to raise_error(ArgumentError, /missing keyword.*entity_id/)
      end
    end
  end
end
