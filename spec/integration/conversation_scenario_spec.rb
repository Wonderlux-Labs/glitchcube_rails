require "rails_helper"

# Harness scenario (A1): drives the REAL ConversationOrchestrator end-to-end
# with FakeHomeAssistant injected and a canned brain LLM. Asserts on observable
# OUTPUT — what the cube says and does — not on internal mocks. Doubles as a
# golden-master of the happy path (brain → translator dispatch → persistence).
#
# This is the seed of the scenario harness: a "world" (persona + entities) + a
# scripted brain response, run through the orchestrator, with the fake recording
# everything the cube did to its environment.
RSpec.describe "Conversation scenario (harness)", type: :integration do
  let(:session_id) { "scenario_spooky_1" }

  let(:fake_ha) do
    FakeHomeAssistant.new(
      persona: "buddy",
      entities: { "light.cube_inner" => { "state" => "on" } }
    )
  end

  # What the brain LLM "decides": a line to say + plain-English action channels
  # (the shape the two-lane dispatcher consumes).
  let(:narrative) do
    {
      "speech" => "Ooh, making it nice and spooky for you!",
      "continue_conversation" => true,
      "inner_monologue" => "spooky vibes incoming",
      "lights" => "turn the lights deep orange",
      "sound" => "play spooky music"
    }
  end

  # Stand-in for the OpenRouter structured response object.
  let(:brain_response) do
    double(
      "BrainResponse",
      content: narrative.to_json,
      structured_output: narrative,
      model: "test/brain",
      usage: { "total_tokens" => 10 }
    )
  end

  before do
    HomeAssistantService.instance = fake_ha
    allow(LlmService).to receive(:call_with_structured_output).and_return(brain_response)
    # Don't actually run the translator LLM; just assert it was dispatched.
    allow(EnvironmentDirectorJob).to receive(:perform_later)
    Conversation.where(session_id: session_id).destroy_all
  end

  after { HomeAssistantService.reset_instance! }

  it "speaks the brain's words and routes the environment change through the two-lane translator" do
    response = ConversationOrchestrator.new(
      session_id: session_id,
      message: "make it spooky in here",
      context: { device_id: "cube_voice", language: "en" }
    ).call

    # The cube said what the brain decided (HASS-formatted response).
    expect(response.to_s).to include("spooky")

    # The `sound` channel goes to the audio agent on its own lane...
    expect(EnvironmentDirectorJob).to have_received(:perform_later).with(
      hash_including(instruction: "play spooky music", convo_prefix: "cube_sound",
                     agent_id: Rails.configuration.hass_sound_agent)
    )
    # ...and everything else goes to the main action agent.
    expect(EnvironmentDirectorJob).to have_received(:perform_later).with(
      hash_including(instruction: "lights: turn the lights deep orange", convo_prefix: "cube_env",
                     agent_id: Rails.configuration.hass_action_agent)
    )

    # The turn was persisted.
    expect(Conversation.find_by(session_id: session_id)).to be_present
  end

  it "still completes the turn when the camera refresh blows up" do
    # The camera look is fire-and-forget; under an inline/test adapter (or if the
    # enqueue itself fails) the error surfaces right in the orchestrator's stack —
    # it must never take the conversation down with it.
    allow(CameraDescriptionJob).to receive(:perform_later)
      .and_raise("Snapshot capture failed (exit 251)")

    response = ConversationOrchestrator.new(
      session_id: session_id,
      message: "make it spooky in here",
      context: { device_id: "cube_voice", language: "en" }
    ).call

    expect(response.to_s).to include("spooky")
    expect(Conversation.find_by(session_id: session_id)).to be_present
  end

  it "never enqueues the camera job when the camera is disabled in config" do
    allow(Rails.configuration).to receive(:disable_camera).and_return(true)
    allow(CameraDescriptionJob).to receive(:perform_later)

    ConversationOrchestrator.new(
      session_id: session_id,
      message: "make it spooky in here",
      context: { device_id: "cube_voice", language: "en" }
    ).call

    expect(CameraDescriptionJob).not_to have_received(:perform_later)
  end
end
