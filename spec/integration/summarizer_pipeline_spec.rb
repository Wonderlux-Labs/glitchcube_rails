# frozen_string_literal: true

require "rails_helper"

# Integration of the layered summarizer pipeline at the service level (LLM stubbed):
# turns → interaction chunk → persona fold (persona summary + neutral handoff) →
# the NEXT persona's injected context. Asserts the key win: the incoming persona reads
# the outgoing persona's NEUTRAL handoff, not its raw interaction chunk text.
RSpec.describe "Summarizer pipeline", type: :integration do
  let!(:neon) { Persona.create!(slug: "neon", name: "Neon") }
  let!(:jax)  { Persona.create!(slug: "jax", name: "Jax") }

  def turns_for(persona_slug, prefix:, count:, at: 10.minutes.ago)
    convo = create(:conversation, persona: persona_slug)
    count.times { |i| create(:conversation_log, conversation: convo, user_message: "#{prefix}-u#{i}", ai_response: "#{prefix}-a#{i}", created_at: at + i.seconds) }
  end

  it "flows turns → chunk → persona+handoff → next persona's context" do
    turns_for("neon", prefix: "NEON_RAW", count: 3, at: 10.minutes.ago)

    # 1. Interaction chunk for Neon (factual, persona-scoped).
    allow(LlmService).to receive(:call_with_structured_output)
      .and_return(double(structured_output: { "summary" => "Neon greeted a small crowd.",
                                               "active_threads" => "A visitor said they'd bring friends back." }))
    expect(SummarizerService.call("neon").success?).to be(true)
    chunk = Summary.interaction.where(persona: neon).last
    expect(chunk).to be_present
    expect(chunk.metadata_json).not_to have_key("ooc_note")

    # 2. Neon's stint ends → persona fold writes a persona summary AND a neutral handoff.
    #    (Stub the internal flush to a no-op so we control the one generate call.)
    allow(SummarizerService).to receive(:call).with("neon").and_call_original
    allow(SummarizerService).to receive(:call).with("neon").and_return(ServiceResult.success({ skipped: true }))
    allow(LlmService).to receive(:call_with_structured_output)
      .and_return(double(structured_output: {
        "summary" => "You (Neon) warmed up a shy crowd — lean into that.",
        "ooc_note" => "You over-explained; trust the one-liners.",
        "handoff_report" => "Neon warmed up a small, shy crowd early on; one visitor said they'd return with friends."
      }))
    expect(PersonaSummarizerService.call("neon").success?).to be(true)

    persona_row = neon.summaries.where(summary_type: "persona").last
    handoff_row = neon.summaries.where(summary_type: "handoff").last
    expect(persona_row.metadata_json["ooc_note"]).to include("trust the one-liners")
    expect(handoff_row.summary_text).to include("Neon warmed up a small, shy crowd")

    # 3. Jax takes over. Its context surfaces Neon's NEUTRAL handoff, not Neon's raw chunk text
    #    and not Neon's private self-steering.
    context = Prompts::ContextBuilder.build(persona: "jax")
    expect(context).to include("Neon warmed up a small, shy crowd")   # neutral handoff
    expect(context).not_to include("NEON_RAW")                        # not raw turns
    expect(context).not_to include("trust the one-liners")            # not Neon's private ooc
    expect(context).not_to include("You (Neon) warmed up")            # not Neon's private self-memory
  end
end
