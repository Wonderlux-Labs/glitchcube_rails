# frozen_string_literal: true

require "rails_helper"

# Script-preset tool: picks a RANDOM sound-reactive WLED effect and cranks brightness,
# both strips, via script.set_cube_lights. No required args.
RSpec.describe Tools::Lights::DanceMode, :allow_ha_calls do
  let(:fake_ha) { FakeHomeAssistant.new }

  before { HomeAssistantService.instance = fake_ha }
  after { HomeAssistantService.reset_instance! }

  def last_vars
    fake_ha.service_calls_for("script").last[:data][:variables]
  end

  it "fires script.set_cube_lights with a sound-reactive effect on both strips, bright" do
    Tools::Lights::DanceMode.call

    call = fake_ha.service_calls_for("script").last
    expect(call[:data][:entity_id]).to eq("script.set_cube_lights")
    expect(last_vars[:led_strip]).to eq("both")
    expect(Tools::Lights::DanceMode::EFFECTS).to include(last_vars[:effect])
    expect(last_vars[:brightness]).to be >= 80
  end

  it "returns a success response with the service call" do
    result = Tools::Lights::DanceMode.call

    expect(result[:success]).to be(true)
    expect(result[:service_calls]).to include(hash_including(domain: "script", service: "turn_on"))
  end

  it "exposes an OpenRouter tool named set_lights_to_dance_mode" do
    expect(Tools::Lights::DanceMode.definition.name).to eq("set_lights_to_dance_mode")
  end
end
