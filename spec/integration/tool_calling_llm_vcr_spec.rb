# frozen_string_literal: true

require "rails_helper"

# VCR-backed translator test: sends a plain-English desired change to a REAL model with
# our REAL tool definitions (recorded once, replayed in CI with a dummy key), and shows
# the model picks sensible tools with sensible args — which then execute as the real HASS
# script calls on FakeHomeAssistant. This is the one spec that exercises the model's
# judgment end-to-end; the pure-wiring version (stubbed LLM) lives in
# tool_calling_scenario_spec.rb, and the loop/validation logic in tool_calling_service_spec.rb.
#
# Model is pinned (not the config default) so the cassette is reproducible. Re-record with:
#   VCR_RECORD=all bundle exec rspec spec/integration/tool_calling_llm_vcr_spec.rb
RSpec.describe "Tool-calling translator (real model, VCR)", :allow_ha_calls, :vcr, type: :integration do
  TRANSLATOR_MODEL = "google/gemini-2.5-flash"

  let(:fake_ha) { FakeHomeAssistant.new(persona: "jax") }
  subject(:translator) { ToolCallingService.new }

  before do
    HomeAssistantService.instance = fake_ha
    Rails.configuration.hass_tool_calling_model = TRANSLATOR_MODEL
  end

  after do
    HomeAssistantService.reset_instance!
    Rails.configuration.hass_tool_calling_model = Rails.configuration.ai_model
  end

  it "decodes a lights + marquee request into set_cube_lights and show_marquee_message" do
    result = translator.execute_intent(
      "lights: make my whole body hot pink, slow gentle breathing. marquee: put JAX on the sign",
      lane: :action
    )

    expect(result[:success]).to be(true)
    names = result[:tool_calls].map { |c| c[:name] }
    expect(names).to include("set_cube_lights", "show_marquee_message")

    # Sensible args: a hot-pink color reads as red-dominant RGB, and the sign says JAX.
    light = result[:tool_calls].find { |c| c[:name] == "set_cube_lights" }
    rgb = light[:arguments]["color"].to_s.split(",").map { |v| v.strip.to_i }
    expect(rgb.length).to eq(3)
    expect(rgb[0]).to be > rgb[1] # pink → more red than green

    marquee = result[:tool_calls].find { |c| c[:name] == "show_marquee_message" }
    expect(marquee[:arguments]["message"].to_s.upcase).to include("JAX")

    # And it actually fired the real HASS scripts.
    entities = fake_ha.service_calls_for("script").map { |c| c[:data][:entity_id] }
    expect(entities).to include("script.set_cube_lights", "script.awtrix_marquee_message")
  end

  it "decodes a background-jukebox request into play_music with the artist-title and a low volume" do
    result = translator.execute_intent(
      "play Nina Simone's song Feeling Good, quietly in the background",
      lane: :sound
    )

    expect(result[:success]).to be(true)
    play = result[:tool_calls].find { |c| c[:name] == "play_music" }
    expect(play).to be_present
    expect(play[:arguments]["query"].to_s).to match(/nina simone|feeling good/i)
    expect(play[:arguments]["volume"].to_i).to be_between(1, 45) # "quietly/background"

    jukebox = fake_ha.service_calls_for("script").find { |c| c[:data][:entity_id] == "script.play_music_on_jukebox" }
    expect(jukebox).to be_present
    expect(jukebox[:data][:variables][:query].to_s).to match(/nina simone|feeling good/i)
  end
end
