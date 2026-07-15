# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Shows::GlitchShort do
  let(:fake_ha) { FakeHomeAssistant.new(persona: "jax") }
  let(:clip) { "/tmp/glitch_efx/short/stab.mp3" }
  let(:show) { described_class.new }

  before do
    HomeAssistantService.instance = fake_ha
    allow(HostAudio).to receive(:play)
    allow(HostAudio).to receive(:random_glitch_efx).with(:short).and_return(clip)
    allow(show).to receive(:pause) # neutralize the real sleeps between beats
  end

  after { HomeAssistantService.reset_instance! }

  it 'plays one random short glitch clip to its natural end (uncapped)' do
    show.call

    expect(HostAudio).to have_received(:play).with(clip, max_seconds: nil)
    expect(HostAudio).to have_received(:random_glitch_efx).with(:short)
  end

  it 'glitches the WLED head+body strips' do
    show.call

    light_calls = fake_ha.service_calls_for("light")
    expect(light_calls).not_to be_empty
    touched = light_calls.flat_map { |c| Array(c[:data][:entity_id]) }.uniq
    expect(touched).to all(satisfy { |e| Shows::Base::WLED_LIGHTS.include?(e) })
  end

  it 'saves the light state first and restores it after (even mid-crash safe)' do
    show.call

    scene_calls = fake_ha.service_calls_for("scene")
    create = scene_calls.find { |c| c[:service] == "create" }
    restore = scene_calls.find { |c| c[:service] == "turn_on" }

    expect(create[:data][:snapshot_entities]).to eq(Shows::Base::WLED_LIGHTS)
    expect(restore[:data][:entity_id]).to eq(Shows::Base::RESTORE_SCENE)

    calls = fake_ha.service_calls
    snapshot_at = calls.index { |c| c[:domain] == "scene" && c[:service] == "create" }
    first_glitch_at = calls.index { |c| c[:domain] == "light" }
    restore_at = calls.index { |c| c[:domain] == "scene" && c[:service] == "turn_on" }
    expect(snapshot_at).to be < first_glitch_at
    expect(first_glitch_at).to be < restore_at
  end

  it 'runs in performance mode and mutes the mic (switching flag) for the duration' do
    show.call

    mode = fake_ha.service_calls_for("input_select").select { |c| c[:data][:entity_id] == "input_select.cube_mode" }
    expect(mode.map { |c| c[:data][:option] }).to eq(%w[performance conversation])

    flag = fake_ha.service_calls_for("input_boolean").select { |c| c[:data][:entity_id] == "input_boolean.persona_switching" }
    expect(flag.map { |c| c[:service] }).to eq(%w[turn_on turn_off])
  end

  it 'restores the lights and tears down cleanly even when playback crashes' do
    allow(HostAudio).to receive(:play).and_raise("ffplay exploded")

    # The failure surfaces at Thread#join and propagates loudly, but every
    # ensure runs first: lights restored, mic unmuted, cube back to conversation.
    expect { show.call }.to raise_error("ffplay exploded")

    expect(fake_ha.service_calls_for("scene").map { |c| c[:service] }).to include("turn_on")
    mode = fake_ha.service_calls_for("input_select").map { |c| c[:data][:option] }
    expect(mode.last).to eq("conversation")
    flag = fake_ha.service_calls_for("input_boolean").map { |c| c[:service] }
    expect(flag.last).to eq("turn_off")
  end

  it 'still runs a lights-only burst when the glitch dir is empty' do
    allow(HostAudio).to receive(:random_glitch_efx).with(:short).and_return(nil)

    show.call

    expect(HostAudio).not_to have_received(:play)
    expect(fake_ha.service_calls_for("light")).not_to be_empty
    expect(fake_ha.service_calls_for("scene").map { |c| c[:service] }).to include("create", "turn_on")
  end
end
