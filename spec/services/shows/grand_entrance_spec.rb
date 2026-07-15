# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Shows::GrandEntrance do
  let(:fake_ha) { FakeHomeAssistant.new(persona: "jax") }
  let(:arrival_speech) { "I AM JAX AND THIS CUBE BELONGS TO ME NOW." }
  let(:orchestrator) do
    instance_double(
      ConversationOrchestrator,
      call: { response: { speech: { plain: { speech: arrival_speech } } } }
    )
  end
  let(:songs_dir) { Pathname.new(Dir.mktmpdir) }
  let(:show) { described_class.new(persona: "jax") }

  before do
    HomeAssistantService.instance = fake_ha
    allow(HostAudio).to receive(:play)
    allow(HostAudio).to receive(:say)
    allow(ConversationOrchestrator).to receive(:new).and_return(orchestrator)

    FileUtils.touch(songs_dir.join("theme_a.mp3"))
    FileUtils.touch(songs_dir.join("theme_b.mp3"))
    stub_const("HostAudio::THEME_SONGS_DIR", songs_dir)
  end

  after do
    HomeAssistantService.reset_instance!
    FileUtils.remove_entry(songs_dir)
  end

  # The mic mute + media_stop silencing hangs off the boolean HASS-side (the
  # "Persona switching: silence during the show" automation), so the show itself
  # only needs to flip the flag reliably.
  it 'raises the switching flag and always drops it when the show ends' do
    show.call

    boolean_calls = fake_ha.service_calls_for("input_boolean")
    expect(boolean_calls.map { |c| c[:service] }).to eq(%w[turn_on turn_off])
    expect(boolean_calls.map { |c| c[:data][:entity_id] }.uniq)
      .to eq([ "input_boolean.persona_switching" ])
  end

  # cube_mode is the whole-cube status flag: a show flips it to "performance" and
  # returns it to "conversation" after (separate from the persona_switching flag).
  it 'runs the show in performance mode and returns to conversation when it ends' do
    show.call

    mode_calls = cube_mode_calls
    expect(mode_calls.map { |c| c[:service] }).to eq(%w[select_option select_option])
    expect(mode_calls.map { |c| c[:data][:option] }).to eq(%w[performance conversation])
  end

  it 'wraps the entire show: performance up before the switching flag, conversation after arrival' do
    show.call

    calls = fake_ha.service_calls
    perf_at = calls.index { |c| c[:domain] == "input_select" && c[:data][:option] == "performance" }
    flag_up_at = calls.index { |c| c[:domain] == "input_boolean" && c[:service] == "turn_on" }
    arrival_at = calls.index { |c| c[:domain] == "assist_satellite" }
    conv_at = calls.index { |c| c[:domain] == "input_select" && c[:data][:option] == "conversation" }

    expect(perf_at).to be < flag_up_at
    expect(arrival_at).to be < conv_at
  end

  it 'returns cube_mode to conversation even when the show crashes' do
    allow(HostAudio).to receive(:play).and_raise("ffplay exploded")

    expect { show.call }.to raise_error("ffplay exploded")

    expect(cube_mode_calls.map { |c| c[:data][:option] }).to eq(%w[performance conversation])
  end

  it 'announces the anomaly on the host speaker, marquee, and lights' do
    show.call

    expect(HostAudio).to have_received(:say) do |line|
      expect(described_class::ANOMALY_LINES).to include(line)
    end

    marquee_messages = marquee_calls.map { |c| c[:data].dig(:variables, :message) }
    expect(marquee_messages.any? { |m| described_class::TRANSITION_MESSAGES.include?(m) }).to be true

    light_call = fake_ha.service_calls_for("script")
      .find { |c| c[:data][:entity_id] == "script.set_top_light_effect" }
    expect(described_class::GLITCH_SCENES).to include(light_call[:data].dig(:variables, :effect))
  end

  # HASS script service calls BLOCK until the script finishes (the marquee script
  # holds for the whole message duration) — shows must fire-and-forget.
  it 'fires HASS scripts non-blocking via script.turn_on' do
    show.call

    expect(fake_ha.service_calls_for("script").map { |c| c[:service] }.uniq).to eq([ "turn_on" ])
  end

  it 'plays a random theme song from the rails media dir, capped at 60 seconds' do
    show.call

    expect(HostAudio).to have_received(:play) do |path, max_seconds:, **|
      expect(path.to_s).to start_with(songs_dir.to_s)
      expect(path.to_s).to end_with(".mp3")
      expect(max_seconds).to eq(60)
    end
  end

  it 'skips the theme song when none are present, and the show goes on' do
    FileUtils.rm(Dir[songs_dir.join("*.mp3")])

    show.call

    expect(HostAudio).not_to have_received(:play)
    expect(fake_ha.service_calls_for("assist_satellite")).not_to be_empty
  end

  it 'runs a real orchestrator turn and starts a satellite conversation with its speech' do
    show.call

    expect(ConversationOrchestrator).to have_received(:new) do |session_id:, message:, context:|
      expect(session_id).to start_with("grand_entrance_")
      expect(message).to match(/announce/i)
      expect(context[:source]).to eq("grand_entrance")
    end

    call = fake_ha.service_calls_for("assist_satellite").last
    expect(call[:service]).to eq("start_conversation")
    expect(call[:data][:entity_id]).to eq("assist_satellite.cube_cube_voice_assist_satellite")
    expect(call[:data][:start_message]).to eq(arrival_speech)
  end

  it 'announces the arrival on the marquee after the wind-down' do
    show.call

    arrival = marquee_calls.map { |c| c[:data].dig(:variables, :message) }.last
    expect(arrival).to eq("JAX HAS ARRIVED")
  end

  it 'runs the whole show inside the switching flag and speaks last' do
    show.call

    calls = fake_ha.service_calls.map { |c| [ c[:domain], c[:service] ] }
    flag_up_at = calls.index(%w[input_boolean turn_on])
    flag_down_at = calls.index(%w[input_boolean turn_off])
    arrival_at = calls.index(%w[assist_satellite start_conversation])

    expect(flag_up_at).to be < flag_down_at
    expect(flag_down_at).to be < arrival_at
  end

  it 'drops the switching flag even when the show crashes mid-song' do
    allow(HostAudio).to receive(:play).and_raise("ffplay exploded")

    expect { show.call }.to raise_error("ffplay exploded")

    expect(fake_ha.service_calls_for("input_boolean").map { |c| c[:service] }).to eq(%w[turn_on turn_off])
    expect(fake_ha.service_calls_for("assist_satellite")).to be_empty
  end

  def marquee_calls
    fake_ha.service_calls_for("script")
      .select { |c| c[:data][:entity_id] == "script.awtrix_marquee_message" }
  end

  def cube_mode_calls
    fake_ha.service_calls_for("input_select")
      .select { |c| c[:data][:entity_id] == "input_select.cube_mode" }
  end
end
