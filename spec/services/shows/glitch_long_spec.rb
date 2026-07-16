# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Shows::GlitchLong do
  let(:fake_ha) { FakeHomeAssistant.new(persona: "jax") }
  let(:show) { described_class.new }

  before do
    HomeAssistantService.instance = fake_ha
    allow(HostAudio).to receive(:play)
    allow(HostAudio).to receive(:random_glitch_efx) { |kind| "/tmp/glitch_efx/#{kind}/clip.mp3" }
    allow(show).to receive(:pause) # neutralize the real sleeps between beats
  end

  after { HomeAssistantService.reset_instance! }

  it 'builds three segments: a long bed, a 5s short stab, another long bed' do
    segs = show.send(:segments)

    expect(segs.map(&:first)).to eq(%i[long short long])
    expect(segs[0][1]).to be_between(20, 40)
    expect(segs[1][1]).to eq(5)
    expect(segs[2][1]).to be_between(20, 40)
  end

  it 'plays long -> short -> long, each capped at its segment length, in order' do
    allow(show).to receive(:segments).and_return([ [ :long, 30 ], [ :short, 5 ], [ :long, 25 ] ])

    show.call

    expect(HostAudio).to have_received(:play).with("/tmp/glitch_efx/long/clip.mp3", max_seconds: 30, volume: a_value_between(25, 50)).ordered
    expect(HostAudio).to have_received(:play).with("/tmp/glitch_efx/short/clip.mp3", max_seconds: 5, volume: a_value_between(25, 50)).ordered
    expect(HostAudio).to have_received(:play).with("/tmp/glitch_efx/long/clip.mp3", max_seconds: 25, volume: a_value_between(25, 50)).ordered
    expect(HostAudio).to have_received(:random_glitch_efx).with(:long).twice
    expect(HostAudio).to have_received(:random_glitch_efx).with(:short).once
  end

  it 'glitches the WLED head+body strips throughout' do
    show.call

    light_calls = fake_ha.service_calls_for("light")
    expect(light_calls).not_to be_empty
    touched = light_calls.flat_map { |c| Array(c[:data][:entity_id]) }.uniq
    expect(touched).to all(satisfy { |e| Shows::Base::WLED_LIGHTS.include?(e) })
  end

  it 'saves the light state first and restores it after the whole show' do
    show.call

    calls = fake_ha.service_calls
    snapshot_at = calls.index { |c| c[:domain] == "scene" && c[:service] == "create" }
    restore_at = calls.index { |c| c[:domain] == "scene" && c[:service] == "turn_on" }
    last_glitch_at = calls.rindex { |c| c[:domain] == "light" }

    expect(snapshot_at).to be < last_glitch_at
    expect(last_glitch_at).to be < restore_at

    create = calls.find { |c| c[:domain] == "scene" && c[:service] == "create" }
    expect(create[:data][:snapshot_entities]).to eq(Shows::Base::WLED_LIGHTS)
  end

  it 'runs in performance mode and mutes the mic for the duration' do
    show.call

    mode = fake_ha.service_calls_for("input_select").select { |c| c[:data][:entity_id] == "input_select.cube_mode" }
    expect(mode.map { |c| c[:data][:option] }).to eq(%w[performance conversation])

    flag = fake_ha.service_calls_for("input_boolean").select { |c| c[:data][:entity_id] == "input_boolean.persona_switching" }
    expect(flag.map { |c| c[:service] }).to eq(%w[turn_on turn_off])
  end

  it 'restores the lights and tears down cleanly even when playback crashes' do
    allow(HostAudio).to receive(:play).and_raise("ffplay exploded")

    expect { show.call }.to raise_error("ffplay exploded")

    expect(fake_ha.service_calls_for("scene").map { |c| c[:service] }).to include("turn_on")
    mode = fake_ha.service_calls_for("input_select").map { |c| c[:data][:option] }
    expect(mode.last).to eq("conversation")
  end
end
