# frozen_string_literal: true

require "rails_helper"

# Script-preset tool: picks a RANDOM calm effect, warm color, moderate brightness,
# both strips, via script.set_cube_lights.
RSpec.describe Tools::Lights::JazzMode, :allow_ha_calls do
  let(:fake_ha) { FakeHomeAssistant.new }

  before { HomeAssistantService.instance = fake_ha }
  after { HomeAssistantService.reset_instance! }

  def last_vars
    fake_ha.service_calls_for("script").last[:data][:variables]
  end

  it "fires script.set_cube_lights with a calm effect on both strips at moderate brightness" do
    Tools::Lights::JazzMode.call

    call = fake_ha.service_calls_for("script").last
    expect(call[:data][:entity_id]).to eq("script.set_cube_lights")
    expect(last_vars[:led_strip]).to eq("both")
    expect(Tools::Lights::JazzMode::EFFECTS).to include(last_vars[:effect])
    expect(last_vars[:brightness]).to be_between(20, 70)
    expect(last_vars[:color]).to be_a(Array)
  end

  it "exposes an OpenRouter tool named set_lights_to_jazz_mode" do
    expect(Tools::Lights::JazzMode.definition.name).to eq("set_lights_to_jazz_mode")
  end
end
