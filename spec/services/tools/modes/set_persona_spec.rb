# frozen_string_literal: true

require "rails_helper"

# Wraps script.set_persona_quick — a quiet, fanfare-free persona switch. persona is
# optional; omitting it lets the script pick a random one.
RSpec.describe Tools::Modes::SetPersona, :allow_ha_calls do
  let(:fake_ha) { FakeHomeAssistant.new }

  before { HomeAssistantService.instance = fake_ha }
  after { HomeAssistantService.reset_instance! }

  def last_call
    fake_ha.service_calls_for("script").last
  end

  it "fires set_persona_quick with the named persona" do
    Tools::Modes::SetPersona.call(persona: "jax")

    expect(last_call[:data][:entity_id]).to eq("script.set_persona_quick")
    expect(last_call[:data][:variables][:persona]).to eq("jax")
  end

  it "fires with no persona variable when omitted (script randomizes)" do
    Tools::Modes::SetPersona.call

    expect(last_call[:data][:entity_id]).to eq("script.set_persona_quick")
    expect(last_call[:data][:variables]).to eq({})
  end

  it "is named set_persona" do
    expect(Tools::Modes::SetPersona.definition.name).to eq("set_persona")
  end
end
