# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::Lights::SetEffect, type: :service do
  include ToolTestHelpers

  before do
    mock_entities
    mock_service_call({})
  end

  describe "#call" do
    context "when called with symbol keys (working case)" do
      it "executes successfully" do
        result = described_class.call(
          entity_id: "light.cube_voice_ring",
          effect: "theater_chase_rainbow_fast"
        )

        expect(result[:success]).to be_falsy # Because entity doesn't support effects in mock
        expect(result[:error]).to include("does not support effects")
      end
    end

    context "when called via AsyncToolJob with string keys (failing case)" do
      it "should execute successfully with string-keyed arguments from JSON" do
        # This reproduces the exact scenario from the error logs
        string_arguments = {
          "entity_id" => "light.cube_voice_ring",
          "effect" => "theater_chase_rainbow_fast"
        }

        # This test SHOULD FAIL initially due to the string key issue
        # Then pass after we fix the keyword argument conversion
        job_result = AsyncToolJob.perform_now(
          'set_light_effect',
          string_arguments,
          'test_session',
          'test_conversation'
        )

        expect(job_result).to be_a(Hash)
        expect(job_result[:success]).to be_falsy # Tool should execute but fail validation (entity doesn't support effects)
        expect(job_result[:error]).to include("does not support effects")
        # Should NOT fail with "missing keywords: :entity_id, :effect"
        expect(job_result[:error]).not_to include("missing keywords")
      end
    end

    context "when using Tools::Registry.execute_tool directly with string keys" do
      it "should handle string-keyed arguments" do
        # This reproduces the lower-level issue
        string_arguments = {
          "entity_id" => "light.cube_voice_ring", 
          "effect" => "theater_chase_rainbow_fast"
        }

        # This should fail with "missing keywords" before our fix
        result = Tools::Registry.execute_tool('set_light_effect', **string_arguments)
        
        expect(result).to be_a(Hash)
        expect(result[:error]).not_to include("missing keywords")
      end
    end
  end
end