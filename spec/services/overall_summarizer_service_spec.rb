# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OverallSummarizerService do
  def stub_llm(summary:, ooc_note: nil)
    payload = { "summary" => summary }
    payload["ooc_note"] = ooc_note unless ooc_note.nil?
    allow(LlmService).to receive(:call_with_structured_output).and_return(double(structured_output: payload))
  end

  def interaction(text, ooc: nil, facts: nil, created_at: 1.minute.ago, mc: 5)
    create(:summary, summary_type: "interaction", summary_text: text,
           metadata: { ooc_note: ooc, real_world_facts: facts }.compact.to_json,
           created_at: created_at, end_time: created_at, message_count: mc)
  end

  context "first run" do
    before do
      interaction("Crash was salty at 3am", created_at: 3.minutes.ago)
      interaction("Zorp got cosmic", created_at: 2.minutes.ago)
    end

    it "creates the single overall summary from the interaction summaries" do
      stub_llm(summary: "Overall: a salty-then-cosmic night.")

      result = described_class.call

      expect(result.success?).to be(true)
      expect(result.data[:folded]).to eq(2)
      expect(Summary.by_type("overall").count).to eq(1)
      expect(Summary.by_type("overall").first.summary_text).to eq("Overall: a salty-then-cosmic night.")
    end

    it "feeds the interaction summaries, their facts, AND their ooc notes into the prompt" do
      interaction("Buddy leaned on a bit", ooc: "watch the repeated catchphrase",
                  facts: "Party at the Corral at 2am", created_at: 1.minute.ago)

      expect(LlmService).to receive(:call_with_structured_output) do |args|
        material = args[:messages].last[:content]
        expect(material).to include("Crash was salty at 3am")
        expect(material).to include("watch the repeated catchphrase")
        expect(material).to include("Party at the Corral at 2am")
        double(structured_output: { "summary" => "ok" })
      end

      described_class.call
    end

    it "stores a system-wide ooc_note when present" do
      stub_llm(summary: "overall", ooc_note: "Devices appear broken across the board — actions keep failing.")
      described_class.call
      expect(Summary.by_type("overall").first.metadata_json["ooc_note"])
        .to eq("Devices appear broken across the board — actions keep failing.")
    end
  end

  context "subsequent run — evolving the overall (versioned)" do
    it "creates a new version reading the latest as its base, folding only newer summaries" do
      interaction("old stuff", created_at: 10.minutes.ago)
      stub_llm(summary: "v1")
      described_class.call
      expect(Summary.by_type("overall").recent.first.summary_text).to eq("v1")

      interaction("new stuff happened", created_at: 1.minute.ago)

      expect(LlmService).to receive(:call_with_structured_output) do |args|
        material = args[:messages].last[:content]
        expect(material).to include("v1")             # latest overall handed back in
        expect(material).to include("new stuff happened")
        expect(material).not_to include("old stuff")  # already folded
        double(structured_output: { "summary" => "v2" })
      end

      result = described_class.call

      expect(Summary.by_type("overall").count).to eq(2)                         # versioned — history kept
      expect(Summary.by_type("overall").recent.first.summary_text).to eq("v2")  # latest is "the" overall
      expect(result.data[:folded]).to eq(1)
    end
  end

  context "no new interaction summaries" do
    it "skips without creating an overall summary" do
      result = described_class.call
      expect(result.data[:skipped]).to be(true)
      expect(Summary.by_type("overall")).to be_empty
    end
  end
end
