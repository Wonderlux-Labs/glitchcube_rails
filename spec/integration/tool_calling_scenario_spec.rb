# frozen_string_literal: true

require "rails_helper"

# End-to-end harness for the in-Rails tool-calling path (everything EXCEPT the brain and
# the translator model's judgment). A brain-style channel hash goes through the REAL
# ConversationOrchestrator::ActionExecutor → EnvironmentDirectorJob → ToolCallingService
# → Tools::Registry → Tools → HomeAssistantService, and we assert the cube's plain-English
# intent lands as the actual HASS *script* calls on FakeHomeAssistant.
#
# No live HASS and no live LLM: because our tools always call real HASS scripts/services,
# FakeHomeAssistant recording those calls IS the proof they'd fire on a real box. The
# translator LLM is stubbed to decode each lane the way a real tool-calling model would —
# the point here is the execution wiring, not the model's choice (that's covered, with the
# validation/retry loop, in spec/services/tool_calling_service_spec.rb).
RSpec.describe "Tool-calling scenario (harness)", :allow_ha_calls, type: :integration do
  include ActiveJob::TestHelper

  let(:fake_ha) { FakeHomeAssistant.new(persona: "jax") }
  let(:conversation) { create(:conversation) }

  before { HomeAssistantService.instance = fake_ha }
  after { HomeAssistantService.reset_instance! }

  def tool_call(name, args)
    OpenRouter::ToolCall.new(
      "id" => SecureRandom.hex(4),
      "type" => "function",
      "function" => { "name" => name, "arguments" => args.to_json }
    )
  end

  # Stub the translator LLM: hand back the tool calls a real model would pick for whichever
  # lane it was invoked on (the sound lane is the one with play_music available).
  def stub_translator!(action_calls: [], sound_calls: [])
    allow(LlmService).to receive(:call_with_tools) do |tools:, **_rest|
      calls = tools.map(&:name).include?("play_music") ? sound_calls : action_calls
      OpenStruct.new(tool_calls: calls, content: nil)
    end
  end

  # Drive the real two-lane dispatch and run the enqueued background jobs inline.
  def run_turn(channels)
    perform_enqueued_jobs do
      ConversationOrchestrator::ActionExecutor.call(
        llm_response: channels,
        session_id: conversation.session_id,
        conversation_id: conversation.id,
        user_message: "make it yours",
        persona: "jax"
      )
    end
  end

  def script_calls_by_entity
    fake_ha.service_calls_for("script").index_by { |c| c[:data][:entity_id] }
  end

  it "turns a lights + marquee intent into the real set_cube_lights and marquee script calls" do
    stub_translator!(
      action_calls: [
        tool_call("set_cube_lights", { "led_strip" => "both", "color" => "255,0,180", "effect" => "Breathe" }),
        tool_call("show_marquee_message", { "message" => "JAX IS IN" })
      ]
    )

    run_turn("lights" => "hot pink, slow breathing", "marquee" => "JAX IS IN")

    by_entity = script_calls_by_entity
    expect(by_entity.keys).to include("script.set_cube_lights", "script.awtrix_marquee_message")
    expect(by_entity["script.set_cube_lights"][:data][:variables]).to include(color: [ 255, 0, 180 ], effect: "Breathe")
    expect(by_entity["script.awtrix_marquee_message"][:data][:variables][:message]).to eq("JAX IS IN")

    # ...and the outcome (with exactly what fired) is folded into the conversation for next turn.
    pending = conversation.reload.metadata_json["pending_ha_results"].last
    fired = pending["service_calls"].map { |s| s["data"]["entity_id"] }
    expect(fired).to include("script.set_cube_lights", "script.awtrix_marquee_message")
  end

  it "sends a jukebox request to script.play_music_on_jukebox with the artist/title and volume" do
    stub_translator!(
      sound_calls: [ tool_call("play_music", { "query" => "Nina Simone - Feeling Good", "volume" => 30 }) ]
    )

    run_turn("sound" => "play some quiet Nina Simone")

    jukebox = script_calls_by_entity["script.play_music_on_jukebox"]
    expect(jukebox).to be_present
    expect(jukebox[:data][:variables]).to include(query: "Nina Simone - Feeling Good", volume: 30)
  end
end
