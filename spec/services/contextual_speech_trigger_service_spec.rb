# frozen_string_literal: true

require "rails_helper"

# Focused coverage for the seam change: a proactive contextual-speech turn with an
# [ENVIRONMENT: ...] instruction now runs through the in-Rails ToolCallingService
# (not a HASS conversation agent). The rest of the trigger flow is exercised elsewhere.
RSpec.describe ContextualSpeechTriggerService do
  subject(:service) { described_class.new }

  let(:persona) { "jax" }
  let(:context) { { location: "the woods" } }

  describe "#process_speech_response" do
    it "runs an [ENVIRONMENT: ...] instruction through the translator on the action lane" do
      llm_response = "Lights up! [ENVIRONMENT: make the lights hot pink]"
      result = { success: true, narrative: "Did: set cube lights", tool_calls: [], service_calls: [], error: nil }
      translator = instance_double(ToolCallingService)
      allow(ToolCallingService).to receive(:new).and_return(translator)
      expect(translator).to receive(:execute_intent).with(
        "make the lights hot pink", hash_including(lane: :action, persona: persona)
      ).and_return(result)

      processed = service.send(:process_speech_response, llm_response, persona, context)

      expect(processed[:tool_results]["environment"]).to eq(result)
    end

    it "does not call the translator when there is no environment instruction" do
      allow(ToolCallingService).to receive(:new)

      service.send(:process_speech_response, "Just talking, no actions here.", persona, context)

      expect(ToolCallingService).not_to have_received(:new)
    end
  end
end
