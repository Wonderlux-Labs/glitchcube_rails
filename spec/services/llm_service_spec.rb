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

  describe ".call_with_vision" do
    # LlmService only reads .content off the vision response.
    def vision_resp(content)
      instance_double("OpenRouter::Response", content: content, model: "whatever", usage: {})
    end

    let(:image_path) do
      path = Rails.root.join("tmp/llm_vision_spec.jpg")
      File.binwrite(path, "\xFF\xD8\xFF\xD9".b) # minimal JPEG bytes
      path.to_s
    end
    let(:client) { instance_double(OpenRouter::Client) }

    before { allow(OpenRouter::Client).to receive(:new).and_return(client) }
    after { FileUtils.rm_f(image_path) }

    it "sends the prompt and the image as a base64 data URI, returning the model's text" do
      captured = nil
      allow(client).to receive(:complete) do |messages, **|
        captured = messages
        vision_resp("two people in fuzzy coats")
      end

      result = described_class.call_with_vision(prompt: "what do you see?", image_path: image_path)

      expect(result).to eq("two people in fuzzy coats")
      expect(client).to have_received(:complete).once
      content = captured.first[:content]
      expect(content.first).to eq(type: "text", text: "what do you see?")
      expect(content.last[:image_url][:url]).to start_with("data:image/jpeg;base64,")
    end

    it "retries once on the fallback model when the primary raises" do
      models_called = []
      allow(client).to receive(:complete) do |_messages, model:, **|
        models_called << model
        raise StandardError, "provider 500" if models_called.length == 1

        vision_resp("recovered")
      end

      result = described_class.call_with_vision(prompt: "look", image_path: image_path)

      expect(result).to eq("recovered")
      expect(models_called).to eq([
        Rails.configuration.camera_vision_model,
        Rails.configuration.vision_fallback_model
      ])
    end

    it "retries on the fallback model when the primary returns blank content" do
      allow(client).to receive(:complete).and_return(vision_resp(""), vision_resp("recovered"))

      result = described_class.call_with_vision(prompt: "look", image_path: image_path)

      expect(result).to eq("recovered")
      expect(client).to have_received(:complete).twice
    end

    it "raises when the fallback also comes back empty" do
      allow(client).to receive(:complete).and_return(vision_resp(""), vision_resp(nil))

      expect {
        described_class.call_with_vision(prompt: "look", image_path: image_path)
      }.to raise_error(/no content/)
    end

    it "lets a fallback hard failure propagate" do
      call = 0
      allow(client).to receive(:complete) do
        call += 1
        raise StandardError, "boom #{call}"
      end

      expect {
        described_class.call_with_vision(prompt: "look", image_path: image_path)
      }.to raise_error(StandardError, "boom 2")
    end
  end

  describe ".call_with_local_vision" do
    include WebMock::API

    let(:jpeg_bytes) { "\xFF\xD8\xFF\xD9".b }
    let(:image_path) do
      path = Rails.root.join("tmp/llm_local_vision_spec.jpg")
      File.binwrite(path, jpeg_bytes)
      path.to_s
    end
    let(:ollama_url) { "#{Rails.configuration.local_vision_url}/api/generate" }
    after { FileUtils.rm_f(image_path) }

    it "POSTs the prompt + base64 image to ollama and returns its response text" do
      captured = nil
      stub_request(:post, ollama_url).to_return do |request|
        captured = JSON.parse(request.body)
        { status: 200, body: { response: "one person in a red shirt" }.to_json }
      end

      result = described_class.call_with_local_vision(prompt: "what do you see?", image_path: image_path)

      expect(result).to eq("one person in a red shirt")
      expect(captured["model"]).to eq(Rails.configuration.local_vision_model)
      expect(captured["prompt"]).to eq("what do you see?")
      expect(captured["images"]).to eq([ Base64.strict_encode64(jpeg_bytes) ])
      expect(captured["stream"]).to be(false)
      expect(captured["think"]).to be(false)
    end

    it "falls back to OpenRouter vision when ollama is unreachable" do
      stub_request(:post, ollama_url).to_raise(Errno::ECONNREFUSED)
      allow(described_class).to receive(:call_with_vision).and_return("openrouter recovered")

      result = described_class.call_with_local_vision(prompt: "look", image_path: image_path)

      expect(result).to eq("openrouter recovered")
      expect(described_class).to have_received(:call_with_vision).with(prompt: "look", image_path: image_path)
    end

    it "falls back to OpenRouter vision on a non-200 from ollama" do
      stub_request(:post, ollama_url).to_return(status: 500, body: "kaboom")
      allow(described_class).to receive(:call_with_vision).and_return("openrouter recovered")

      expect(
        described_class.call_with_local_vision(prompt: "look", image_path: image_path)
      ).to eq("openrouter recovered")
    end

    it "falls back to OpenRouter vision when ollama returns a blank description" do
      stub_request(:post, ollama_url).to_return(status: 200, body: { response: "" }.to_json)
      allow(described_class).to receive(:call_with_vision).and_return("openrouter recovered")

      expect(
        described_class.call_with_local_vision(prompt: "look", image_path: image_path)
      ).to eq("openrouter recovered")
    end
  end
end
