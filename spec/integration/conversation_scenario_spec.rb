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

  # What the brain LLM "decides": a line to say + one plain-English environment
  # instruction (the shape the translator consumes).
  let(:narrative) do
    {
      "speech_text" => "Ooh, making it nice and spooky for you!",
      "continue_conversation" => true,
      "inner_thoughts" => "spooky vibes incoming",
      "current_mood" => "playful",
      "environment_instruction" => "turn the lights deep orange and play spooky music"
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

  it "speaks the brain's words and routes the environment change through the single translator" do
    response = ConversationOrchestrator.new(
      session_id: session_id,
      message: "make it spooky in here",
      context: { device_id: "cube_voice", language: "en" }
    ).call

    # The cube said what the brain decided (HASS-formatted response).
    expect(response.to_s).to include("spooky")

    # All environment changes went through ONE translator job (no per-domain
    # fan-out), carrying the brain's plain-English instruction verbatim.
    expect(EnvironmentDirectorJob).to have_received(:perform_later).with(
      hash_including(instruction: "turn the lights deep orange and play spooky music")
    )

    # The turn was persisted.
    expect(Conversation.find_by(session_id: session_id)).to be_present
  end
end
