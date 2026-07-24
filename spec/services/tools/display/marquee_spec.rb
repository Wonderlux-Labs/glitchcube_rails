# frozen_string_literal: true

require "rails_helper"

# Wraps script.awtrix_marquee_message (message required) and script.awtrix_marquee_clear.
RSpec.describe "Marquee tools", :allow_ha_calls do
  let(:fake_ha) { FakeHomeAssistant.new }

  before { HomeAssistantService.instance = fake_ha }
  after { HomeAssistantService.reset_instance! }

  def last_call
    fake_ha.service_calls_for("script").last
  end

  describe Tools::Display::Marquee do
    it "fires awtrix_marquee_message with the message" do
      Tools::Display::Marquee.call(message: "JAX DOESN'T PLAY THAT")

      expect(last_call[:data][:entity_id]).to eq("script.awtrix_marquee_message")
      expect(last_call[:data][:variables][:message]).to eq("JAX DOESN'T PLAY THAT")
    end

    it "forwards optional color, rainbow, duration, icon and repeat when set" do
      Tools::Display::Marquee.call(message: "HI", color: "#FF00AA", rainbow: true, duration: 30, icon: "87", repeat: 3)

      vars = last_call[:data][:variables]
      expect(vars).to include(color: "#FF00AA", rainbow: true, duration: 30, icon: "87", repeat: 3)
    end

    it "omits optional keys that were not provided" do
      Tools::Display::Marquee.call(message: "HI")

      expect(last_call[:data][:variables].keys).to eq([ :message ])
    end

    it "requires a message" do
      result = Tools::Display::Marquee.call(message: "")

      expect(result[:success]).to be(false)
      expect(fake_ha.service_calls).to be_empty
    end

    it "is named show_marquee_message" do
      expect(Tools::Display::Marquee.definition.name).to eq("show_marquee_message")
    end

    it "flags an out-of-range duration and a bad hex color at the definition layer (drives the retry loop)" do
      errors = []
      Tools::Display::Marquee.definition.validation_blocks.each do |b|
        b.call({ "message" => "HI", "duration" => 500, "color" => "purple" }, errors)
      end

      expect(errors.join).to match(/duration/i)
      expect(errors.join).to match(/color/i)
    end

    it "flags a missing message at the definition layer" do
      errors = []
      Tools::Display::Marquee.definition.validation_blocks.each { |b| b.call({}, errors) }

      expect(errors.join).to match(/message/i)
    end
  end

  describe Tools::Display::ClearMarquee do
    it "fires awtrix_marquee_clear with no variables" do
      Tools::Display::ClearMarquee.call

      expect(last_call[:data][:entity_id]).to eq("script.awtrix_marquee_clear")
      expect(last_call[:data][:variables]).to eq({})
    end

    it "is named clear_marquee" do
      expect(Tools::Display::ClearMarquee.definition.name).to eq("clear_marquee")
    end
  end
end
