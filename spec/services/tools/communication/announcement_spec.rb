# frozen_string_literal: true

require "rails_helper"

# Wraps script.system_announcement — a robotic, non-persona interruption over the
# jukebox speaker. message required; volume optional (script defaults to 75).
RSpec.describe Tools::Communication::Announcement, :allow_ha_calls do
  let(:fake_ha) { FakeHomeAssistant.new }

  before { HomeAssistantService.instance = fake_ha }
  after { HomeAssistantService.reset_instance! }

  def last_call
    fake_ha.service_calls_for("script").last
  end

  it "fires system_announcement with the message" do
    Tools::Communication::Announcement.call(message: "The cube will shut down from boredom.")

    expect(last_call[:data][:entity_id]).to eq("script.system_announcement")
    expect(last_call[:data][:variables][:message]).to eq("The cube will shut down from boredom.")
  end

  it "forwards volume when provided and omits it otherwise" do
    Tools::Communication::Announcement.call(message: "Hi", volume: 40)
    expect(last_call[:data][:variables][:volume]).to eq(40)

    Tools::Communication::Announcement.call(message: "Hi")
    expect(last_call[:data][:variables].keys).to eq([ :message ])
  end

  it "requires a message" do
    result = Tools::Communication::Announcement.call(message: "")

    expect(result[:success]).to be(false)
    expect(fake_ha.service_calls).to be_empty
  end

  it "is named make_announcement" do
    expect(Tools::Communication::Announcement.definition.name).to eq("make_announcement")
  end
end
