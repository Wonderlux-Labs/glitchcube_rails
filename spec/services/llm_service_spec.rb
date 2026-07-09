# frozen_string_literal: true

require "rails_helper"

RSpec.describe LlmService do
  # Minimal stand-in for OpenRouter::Response — LlmService only reads these.
  def resp(structured:, model:, content: "")
    instance_double("OpenRouter::Response",
                    structured_output: structured, model: model, content: content, usage: {})
  end

  let(:schema) { Schemas::NarrativeResponseSchema.schema }
  let(:messages) { [ { role: "user", content: "hi" } ] }
  let(:good) { { "speech" => "hello", "inner_monologue" => "x", "continue_conversation" => true } }

  describe ".call_with_structured_output empty-response recovery" do
    it "silently resends to a secondary model when the primary returns empty structured output" do
      client = instance_double(OpenRouter::Client)
      allow(OpenRouter::Client).to receive(:new).and_return(client)
      # 1st call (primary, glm) → empty; 2nd call (secondary) → good.
      allow(client).to receive(:complete).and_return(
        resp(structured: nil, model: "z-ai/glm-5.2", content: ""),
        resp(structured: good, model: "google/gemini-3.1-flash-lite", content: good.to_json)
      )

      result = described_class.call_with_structured_output(
        messages: messages, response_format: schema, model: "z-ai/glm-5.2"
      )

      expect(result.structured_output).to eq(good)
      expect(result.model).to eq("google/gemini-3.1-flash-lite")
      expect(client).to have_received(:complete).twice
    end

    it "resends to a secondary model when the primary call raises a hard error (bad model id, 5xx)" do
      client = instance_double(OpenRouter::Client)
      allow(OpenRouter::Client).to receive(:new).and_return(client)
      call = 0
      allow(client).to receive(:complete) do
        call += 1
        raise StandardError, "Bad Request: model is not a valid model ID" if call == 1

        resp(structured: good, model: "google/gemini-3.1-flash-lite", content: good.to_json)
      end

      result = described_class.call_with_structured_output(
        messages: messages, response_format: schema, model: "bogus/nonexistent-model"
      )

      expect(result.structured_output).to eq(good)
      expect(result.model).to eq("google/gemini-3.1-flash-lite")
      expect(client).to have_received(:complete).twice
    end

    it "does not retry when the primary already returns structured output" do
      client = instance_double(OpenRouter::Client)
      allow(OpenRouter::Client).to receive(:new).and_return(client)
      allow(client).to receive(:complete).and_return(
        resp(structured: good, model: "z-ai/glm-5.2", content: good.to_json)
      )

      result = described_class.call_with_structured_output(
        messages: messages, response_format: schema, model: "z-ai/glm-5.2"
      )

      expect(result.structured_output).to eq(good)
      expect(client).to have_received(:complete).once
    end
  end
end
