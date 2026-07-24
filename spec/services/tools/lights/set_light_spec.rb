# frozen_string_literal: true

require "rails_helper"

# The generic cube-light tool. It never addresses WLED fixtures directly — it wraps
# script.set_cube_lights (which owns the both/head/body → real-entity routing), invoked
# non-blocking via script.turn_on + variables. We assert on the recorded service call.
RSpec.describe Tools::Lights::SetLight, :allow_ha_calls do
  let(:fake_ha) { FakeHomeAssistant.new }

  before { HomeAssistantService.instance = fake_ha }
  after { HomeAssistantService.reset_instance! }

  def last_script_call
    fake_ha.service_calls_for("script").last
  end

  describe ".call" do
    it "fires script.set_cube_lights via script.turn_on with variables (never light.turn_on)" do
      Tools::Lights::SetLight.call(led_strip: "body", color: "255,0,255", brightness: 80, effect: "Breathe")

      call = last_script_call
      expect(call[:service]).to eq("turn_on")
      expect(call[:data][:entity_id]).to eq("script.set_cube_lights")
      expect(fake_ha.service_calls_for("light")).to be_empty
    end

    it "passes color through as an RGB array the color_rgb selector expects" do
      Tools::Lights::SetLight.call(color: "255,0,255")

      expect(last_script_call[:data][:variables][:color]).to eq([ 255, 0, 255 ])
    end

    it "forwards led_strip, brightness and effect verbatim" do
      Tools::Lights::SetLight.call(led_strip: "head", brightness: 40, effect: "Aurora")

      vars = last_script_call[:data][:variables]
      expect(vars[:led_strip]).to eq("head")
      expect(vars[:brightness]).to eq(40)
      expect(vars[:effect]).to eq("Aurora")
    end

    it "only sends the keys the caller set (so it never clobbers unspecified color/brightness)" do
      Tools::Lights::SetLight.call(led_strip: "both", effect: "Solid")

      vars = last_script_call[:data][:variables]
      expect(vars.keys).to contain_exactly(:led_strip, :effect)
    end

    it "returns a success response describing the service call it made" do
      result = Tools::Lights::SetLight.call(led_strip: "both", color: "10,20,30")

      expect(result[:success]).to be(true)
      expect(result[:service_calls]).to include(
        hash_including(domain: "script", service: "turn_on")
      )
    end

    it "rejects a malformed color instead of firing a call" do
      result = Tools::Lights::SetLight.call(color: "not-a-color")

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/color/i)
      expect(fake_ha.service_calls).to be_empty
    end
  end

  describe ".definition" do
    it "exposes an OpenRouter tool named set_cube_lights with a led_strip enum" do
      definition = Tools::Lights::SetLight.definition

      expect(definition.name).to eq("set_cube_lights")
      params = definition.to_h.dig(:function, :parameters, :properties) ||
               definition.to_h.dig("function", "parameters", "properties")
      strip = params[:led_strip] || params["led_strip"]
      expect(strip[:enum] || strip["enum"]).to contain_exactly("both", "head", "body")
    end

    it "validates a bad color at the definition layer (drives the retry loop)" do
      definition = Tools::Lights::SetLight.definition
      errors = []
      definition.validation_blocks.each { |b| b.call({ "color" => "9,9" }, errors) }

      expect(errors.join).to match(/color/i)
    end
  end
end
