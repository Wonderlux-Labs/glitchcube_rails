# frozen_string_literal: true

require "rails_helper"

# The in-Rails translator LLM. Takes one plain-English instruction from the brain and a
# lane (:action / :sound), asks the tool-calling model which of that lane's tools to
# call, validates each call against its definition (retrying with feedback on validation
# errors), executes the valid ones against Home Assistant, and returns ONE normalized
# struct describing exactly what fired. The LLM itself is the only thing stubbed.
RSpec.describe ToolCallingService, :allow_ha_calls do
  let(:fake_ha) { FakeHomeAssistant.new }

  before { HomeAssistantService.instance = fake_ha }
  after { HomeAssistantService.reset_instance! }

  def tool_call(name, args)
    OpenRouter::ToolCall.new(
      "id" => SecureRandom.hex(4),
      "type" => "function",
      "function" => { "name" => name, "arguments" => args.to_json }
    )
  end

  def llm_response(calls: [], content: nil)
    OpenStruct.new(tool_calls: calls, content: content)
  end

  describe "#execute_intent" do
    it "asks the LLM for only the lane's tools, at low temperature, on the tool-calling model" do
      captured = {}
      allow(LlmService).to receive(:call_with_tools) do |messages:, tools:, model:, **opts|
        captured = { names: tools.map(&:name), model: model, temperature: opts[:temperature] }
        llm_response(calls: [])
      end

      described_class.new.execute_intent("play some jazz quietly", lane: :sound)

      expect(captured[:names]).to include("play_music")
      expect(captured[:names]).not_to include("set_cube_lights")
      expect(captured[:model]).to eq(Rails.configuration.hass_tool_calling_model)
      expect(captured[:temperature]).to eq(0.1)
    end

    it "executes the translated tool call and reports exactly what fired" do
      allow(LlmService).to receive(:call_with_tools).and_return(
        llm_response(calls: [ tool_call("set_cube_lights", { "led_strip" => "both", "color" => "255,0,255" }) ])
      )

      result = described_class.new.execute_intent("make everything magenta", lane: :action)

      expect(result[:success]).to be(true)
      expect(result[:tool_calls].map { |c| c[:name] }).to eq([ "set_cube_lights" ])
      expect(result[:service_calls]).to include(hash_including(domain: "script", service: "turn_on"))
      expect(fake_ha.service_calls_for("script").last[:data][:entity_id]).to eq("script.set_cube_lights")
    end

    it "executes every tool call in a multi-call response" do
      allow(LlmService).to receive(:call_with_tools).and_return(
        llm_response(calls: [
          tool_call("set_cube_lights", { "led_strip" => "both", "effect" => "Aurora" }),
          tool_call("show_marquee_message", { "message" => "HELLO" })
        ])
      )

      result = described_class.new.execute_intent("aurora lights and say hello", lane: :action)

      expect(result[:tool_calls].map { |c| c[:name] }).to contain_exactly("set_cube_lights", "show_marquee_message")
      entities = fake_ha.service_calls_for("script").map { |c| c[:data][:entity_id] }
      expect(entities).to contain_exactly("script.set_cube_lights", "script.awtrix_marquee_message")
    end

    it "retries with error feedback when the first call is invalid, then succeeds" do
      allow(LlmService).to receive(:call_with_tools).and_return(
        llm_response(calls: [ tool_call("set_cube_lights", { "color" => "not-a-color" }) ]),
        llm_response(calls: [ tool_call("set_cube_lights", { "color" => "0,255,0" }) ])
      )

      result = described_class.new.execute_intent("make it green", lane: :action)

      expect(LlmService).to have_received(:call_with_tools).twice
      expect(result[:success]).to be(true)
      expect(fake_ha.service_calls_for("script").last[:data][:variables][:color]).to eq([ 0, 255, 0 ])
    end

    it "returns success with no service calls when the translator decides no action is needed" do
      allow(LlmService).to receive(:call_with_tools).and_return(
        llm_response(calls: [], content: "Nothing to change here.")
      )

      result = described_class.new.execute_intent("just vibes", lane: :action)

      expect(result[:success]).to be(true)
      expect(result[:tool_calls]).to be_empty
      expect(result[:service_calls]).to be_empty
      expect(result[:narrative]).to be_present
    end

    it "gives up after max iterations of invalid calls, reporting the error without firing" do
      allow(LlmService).to receive(:call_with_tools).and_return(
        llm_response(calls: [ tool_call("set_cube_lights", { "color" => "bad" }) ])
      )

      result = described_class.new.execute_intent("green", lane: :action)

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/color/i)
      expect(fake_ha.service_calls).to be_empty
    end

    it "always returns the normalized struct keys" do
      allow(LlmService).to receive(:call_with_tools).and_return(llm_response(calls: []))

      result = described_class.new.execute_intent("x", lane: :action)

      expect(result).to include(:success, :narrative, :tool_calls, :service_calls, :error)
    end

    it "defaults to the action lane when none is given" do
      captured_names = nil
      allow(LlmService).to receive(:call_with_tools) do |tools:, **_|
        captured_names = tools.map(&:name)
        llm_response(calls: [])
      end

      described_class.new.execute_intent("make it purple")

      expect(captured_names).to include("set_cube_lights")
    end
  end
end
