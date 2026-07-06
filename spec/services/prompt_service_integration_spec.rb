# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PromptService, "integration scenarios", type: :service do
  let(:conversation) { create(:conversation) }

  before do
    # Mock CubePersona to avoid HA calls
    allow(CubePersona).to receive(:current_persona).and_return(:buddy)
    allow(HomeAssistantService).to receive(:entity).with("sensor.glitchcube_world_state")
      .and_return({ "attributes" => { "content" => "It is late and quiet." } })
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
    it "caps a very long running-memory summary rather than letting it sprawl" do
      create(:summary, summary_type: "interaction",
             summary_text: "so much happened " * 200, created_at: 1.minute.ago) # ~3400 chars

      service = described_class.new(persona: "buddy", conversation: conversation, extra_context: {})

      expect { service.build }.not_to raise_error
      ctx = service.build[:context]
      expect(ctx).to include("Recently")
      expect(ctx.length).to be < 1500 # each memory blob is clipped (~900), no sprawl
    end

    it "handles special characters in history gracefully" do
      special_conversation = create(:conversation, session_id: "test-session-éñ中文🎭")
      create(:conversation_log, conversation: special_conversation,
             user_message: "héllo 🎭", ai_response: "hí", created_at: 30.seconds.ago)

      service = described_class.new(persona: "buddy", conversation: special_conversation, extra_context: {})

      expect { service.build }.not_to raise_error
      expect(service.build[:messages].map { |m| m[:content] }).to include("héllo 🎭")
    end
  end
end
