# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PersonaSummarizerService do
  let!(:zorp) { Persona.create!(slug: "zorp", name: "Zorp") }

  def stub_llm(summary:, ooc_note: nil, handoff_report: "Zorp did some cosmic readings for a few visitors.")
    payload = { "summary" => summary, "handoff_report" => handoff_report }
    payload["ooc_note"] = ooc_note unless ooc_note.nil?
    allow(LlmService).to receive(:call_with_structured_output)
      .and_return(double(structured_output: payload))
  end

  # A persona interaction chunk (what the fold now reads), scoped to a persona.
  def chunk(persona, text, facts: nil, threads: nil, at: 2.minutes.ago, mc: 3)
    create(:summary, summary_type: "interaction", persona: persona, summary_text: text,
           metadata: { real_world_facts: facts, active_threads: threads }.compact.to_json,
           start_time: at, end_time: at + 1.minute, created_at: at, message_count: mc)
  end

  # Prevent the internal flush from doing real work unless a test wants it.
  before { allow(SummarizerService).to receive(:call) }

  context "a stint with interaction chunks" do
    before do
      chunk(zorp, "ZORP chunk one", at: 3.minutes.ago)
      chunk(zorp, "ZORP chunk two", at: 2.minutes.ago)
    end

    it "flushes the tail turns before folding" do
      expect(SummarizerService).to receive(:call).with("zorp")
      stub_llm(summary: "You leaned cosmic.")
      described_class.call("zorp")
    end

    it "writes a persona summary AND a neutral handoff row in one run" do
      stub_llm(summary: "You leaned cosmic and did some readings.",
               handoff_report: "Zorp read a few visitors and it landed well.")

      result = described_class.call("zorp")

      expect(result.success?).to be(true)
      persona_row = zorp.summaries.where(summary_type: "persona").last
      handoff_row = zorp.summaries.where(summary_type: "handoff").last
      expect(persona_row.summary_text).to eq("You leaned cosmic and did some readings.")
      expect(persona_row.persona).to eq(zorp)
      expect(handoff_row.summary_text).to eq("Zorp read a few visitors and it landed well.")
      expect(handoff_row.persona).to eq(zorp)
      expect(persona_row.message_count).to eq(6) # two chunks × 3
    end

    it "feeds the persona's chunks and character brief into the material" do
      zorp.update!(persona_prompt: "You are Zorp, a cosmic oracle who curses freely.")
      expect(LlmService).to receive(:call_with_structured_output) do |args|
        material = args[:messages].last[:content]
        expect(material).to include("ZORP chunk one")
        expect(material).to include("cosmic oracle who curses freely")
        double(structured_output: { "summary" => "ok", "handoff_report" => "recap" })
      end
      described_class.call("zorp")
    end

    it "stores a self-steering ooc_note on the persona row when present" do
      stub_llm(summary: "cosmic night", ooc_note: "You keep leaning on the butt-reading bit — vary it.")
      described_class.call("zorp")
      expect(zorp.summaries.where(summary_type: "persona").last.metadata_json["ooc_note"])
        .to eq("You keep leaning on the butt-reading bit — vary it.")
    end

    it "does not write a handoff when the model omits the report" do
      stub_llm(summary: "cosmic night", handoff_report: "  ")
      described_class.call("zorp")
      expect(zorp.summaries.where(summary_type: "handoff")).to be_empty
      expect(zorp.summaries.where(summary_type: "persona").count).to eq(1)
    end
  end

  context "subsequent run — versioned + boundary" do
    it "folds only chunks newer than the last fold" do
      chunk(zorp, "OLD chunk", at: 20.minutes.ago)
      stub_llm(summary: "v1")
      described_class.call("zorp")
      expect(zorp.summaries.where(summary_type: "persona").last.summary_text).to eq("v1")

      chunk(zorp, "NEW chunk", at: 1.minute.ago)

      expect(LlmService).to receive(:call_with_structured_output) do |args|
        material = args[:messages].last[:content]
        expect(material).to include("v1")        # prior self-summary handed back in
        expect(material).to include("NEW chunk")
        expect(material).not_to include("OLD chunk") # already folded
        double(structured_output: { "summary" => "v2", "handoff_report" => "recap v2" })
      end

      described_class.call("zorp")

      persona_summaries = zorp.summaries.where(summary_type: "persona").order(:created_at)
      expect(persona_summaries.count).to eq(2)
      expect(persona_summaries.last.summary_text).to eq("v2")
    end
  end

  it "skips when the persona had no chunks" do
    result = described_class.call("zorp")
    expect(result.data[:skipped]).to be(true)
    expect(zorp.summaries.where(summary_type: "persona")).to be_empty
  end

  it "fails for an unknown persona" do
    expect(described_class.call("nobody").success?).to be(false)
  end
end
