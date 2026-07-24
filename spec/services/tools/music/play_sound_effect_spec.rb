# frozen_string_literal: true

require "rails_helper"

# Wraps script.play_sound_effect — a short stinger from a fixed enum.
RSpec.describe Tools::Music::PlaySoundEffect, :allow_ha_calls do
  let(:fake_ha) { FakeHomeAssistant.new }

  before { HomeAssistantService.instance = fake_ha }
  after { HomeAssistantService.reset_instance! }

  def last_call
    fake_ha.service_calls_for("script").last
  end

  it "fires play_sound_effect with the chosen effect" do
    Tools::Music::PlaySoundEffect.call(effect: "Cymbal Crash")

    expect(last_call[:data][:entity_id]).to eq("script.play_sound_effect")
    expect(last_call[:data][:variables][:effect]).to eq("Cymbal Crash")
  end

  it "exposes the effect enum in its definition" do
    definition = Tools::Music::PlaySoundEffect.definition
    props = definition.to_h.dig(:function, :parameters, :properties)
    expect(props[:effect][:enum]).to include("Applause", "Explosion", "Cat Meow")
  end

  it "is named play_sound_effect" do
    expect(Tools::Music::PlaySoundEffect.definition.name).to eq("play_sound_effect")
  end

  it "flags an off-enum effect at the definition layer (drives the retry loop)" do
    errors = []
    Tools::Music::PlaySoundEffect.definition.validation_blocks.each do |b|
      b.call({ "effect" => "Airhorn" }, errors)
    end

    expect(errors.join).to match(/unknown sound effect/i)
  end
end
