# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PromptService, "integration scenarios", type: :service do
  let(:conversation) { create(:conversation) }

  before do
    # Mock CubePersona to avoid HA calls
    allow(CubePersona).to receive(:current_persona).and_return(:buddy)
  end

  describe "real-world error scenarios that should be caught" do
    context "when Home Assistant is unreachable" do
      before do
        allow(HomeAssistantService).to receive(:new).and_raise(Errno::ECONNREFUSED)
      end

      it "builds prompt gracefully without HA context" do
        service = described_class.new(
          persona: "buddy",
          conversation: conversation,
          extra_context: {},
          user_message: "What's my current location?"
        )

        expect { service.build }.not_to raise_error
        result = service.build

        expect(result[:context]).not_to include("current_location")
        expect(result[:system_prompt]).to be_present
        expect(result[:messages]).to be_an(Array)
        expect(result[:tools]).to be_an(Array)
      end
    end
  end

  describe "nil handling that caused production errors" do
    it "handles nil user_message gracefully" do
      service = described_class.new(
        persona: "buddy",
        conversation: conversation,
        extra_context: {},
        user_message: nil
      )

      expect { service.build }.not_to raise_error
      result = service.build
      expect(result[:context]).to be_present
    end

    it "handles nil conversation gracefully" do
      service = described_class.new(
        persona: "buddy",
        conversation: nil,
        extra_context: {}
      )

      expect { service.build }.not_to raise_error
      result = service.build
      expect(result[:messages]).to eq([])
    end

    it "handles nil or invalid persona gracefully" do
      service = described_class.new(
        persona: nil,
        conversation: conversation,
        extra_context: {}
      )

      expect { service.build }.not_to raise_error
      result = service.build
      expect(result[:system_prompt]).to be_present
    end
  end

  describe "context building edge cases" do
    it "handles very long contexts gracefully" do
      large_extra_context = {
        tool_results: (1..50).map { |i| [ "tool_#{i}", { success: true, message: "Result #{i}" * 100 } ] }.to_h
      }

      service = described_class.new(
        persona: "buddy",
        conversation: conversation,
        extra_context: large_extra_context
      )

      expect { service.build }.not_to raise_error
      result = service.build
      expect(result[:context]).to be_present
      expect(result[:context].length).to be > 1000
    end

    it "handles special characters in context gracefully" do
      special_conversation = create(:conversation, session_id: "test-session-éñ中文🎭")

      service = described_class.new(
        persona: "buddy",
        conversation: special_conversation,
        extra_context: { source: "test with émojis 🎯 and unicode" }
      )

      expect { service.build }.not_to raise_error
      result = service.build
      expect(result[:context]).to include("test with émojis 🎯 and unicode")
    end
  end
end
