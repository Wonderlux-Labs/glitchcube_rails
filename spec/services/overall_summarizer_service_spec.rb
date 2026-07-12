# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OverallSummarizerService do
  let!(:zorp) { Persona.create!(slug: "zorp", name: "Zorp") }
  let!(:crash) { Persona.create!(slug: "crash", name: "Crash") }

  def stub_llm(narrative:, durable_facts: nil, recurring_visitors: nil, director_note: nil, active_threads: nil)
    payload = { "shared_narrative" => narrative }
    payload["durable_facts"] = durable_facts unless durable_facts.nil?
    payload["recurring_visitors"] = recurring_visitors unless recurring_visitors.nil?
    payload["director_note"] = director_note unless director_note.nil?
    payload["active_threads"] = active_threads unless active_threads.nil?
    allow(LlmService).to receive(:call_with_structured_output).and_return(double(structured_output: payload))
  end

  def handoff(persona, text, created_at: 1.minute.ago, mc: 5)
    create(:summary, summary_type: "handoff", persona: persona, summary_text: text,
           created_at: created_at, start_time: created_at - 5.minutes, end_time: created_at, message_count: mc)
  end

  context "first run" do
    before do
      handoff(crash, "Crash was salty with a late-night crowd at 3am.", created_at: 3.minutes.ago)
      handoff(zorp, "Zorp got cosmic and read a few visitors.", created_at: 2.minutes.ago)
    end

    it "creates the single overall summary from the HANDOFF reports" do
      stub_llm(narrative: "A salty-then-cosmic night out in the deep playa.")

      result = described_class.call

      expect(result.success?).to be(true)
      expect(result.data[:folded]).to eq(2)
      expect(Summary.by_type("overall").count).to eq(1)
      expect(Summary.by_type("overall").first.summary_text).to eq("A salty-then-cosmic night out in the deep playa.")
    end

    it "feeds the handoff reports (persona-labeled) into the prompt" do
      expect(LlmService).to receive(:call_with_structured_output) do |args|
        material = args[:messages].last[:content]
        expect(material).to include("Crash was salty")
        expect(material).to include("Zorp got cosmic")
        expect(material).to include("Crash") # persona label
        double(structured_output: { "shared_narrative" => "ok" })
      end
      described_class.call
    end

    it "does NOT read raw interaction summaries" do
      create(:summary, summary_type: "interaction", persona: zorp,
             summary_text: "SECRET_INTERACTION_TEXT", created_at: 1.minute.ago)
      expect(LlmService).to receive(:call_with_structured_output) do |args|
        expect(args[:messages].last[:content]).not_to include("SECRET_INTERACTION_TEXT")
        double(structured_output: { "shared_narrative" => "ok" })
      end
      described_class.call
    end

    it "stores durable_facts (the world board) when present" do
      stub_llm(narrative: "overall", durable_facts: "Camp Trashy: possible fashion show tomorrow (visitor-reported).")
      described_class.call
      expect(Summary.by_type("overall").first.metadata_json["durable_facts"])
        .to eq("Camp Trashy: possible fashion show tomorrow (visitor-reported).")
    end

    it "stores recurring_visitors when present" do
      stub_llm(narrative: "overall", recurring_visitors: "Marco: wants a lavender-purple glow, may return by sunrise.")
      described_class.call
      expect(Summary.by_type("overall").first.metadata_json["recurring_visitors"])
        .to eq("Marco: wants a lavender-purple glow, may return by sunrise.")
    end

    it "stores an optional director_note when the model offers one" do
      stub_llm(narrative: "overall", director_note: "Devices appear broken across every stint — actions keep failing.")
      described_class.call
      expect(Summary.by_type("overall").first.metadata_json["director_note"])
        .to eq("Devices appear broken across every stint — actions keep failing.")
    end
  end

  context "carrying the world board forward" do
    it "feeds the prior overall's durable facts back in so they survive when a handoff omits them" do
      # A prior overall knows about Camp Trashy; the new handoff doesn't mention it.
      create(:summary, summary_type: "overall", summary_text: "An earlier story.",
             metadata: { durable_facts: "Camp Trashy: fashion show tomorrow.",
                         recurring_visitors: "Marco: lavender glow." }.to_json,
             start_time: 20.minutes.ago, end_time: 10.minutes.ago, created_at: 10.minutes.ago)
      handoff(zorp, "Zorp chatted with a new crowd about the weather.", created_at: 1.minute.ago)

      expect(LlmService).to receive(:call_with_structured_output) do |args|
        material = args[:messages].last[:content]
        expect(material).to include("Camp Trashy: fashion show tomorrow.")  # carried forward
        expect(material).to include("Marco: lavender glow.")                # carried forward
        double(structured_output: { "shared_narrative" => "updated" })
      end

      described_class.call
    end
  end

  context "subsequent run — evolving the overall (versioned)" do
    it "creates a new version, folding only handoffs newer than the last fold" do
      handoff(zorp, "old handoff", created_at: 10.minutes.ago)
      stub_llm(narrative: "v1")
      described_class.call
      expect(Summary.by_type("overall").recent.first.summary_text).to eq("v1")

      handoff(crash, "new handoff happened", created_at: 1.minute.ago)

      expect(LlmService).to receive(:call_with_structured_output) do |args|
        material = args[:messages].last[:content]
        expect(material).to include("v1")                 # latest overall handed back in
        expect(material).to include("new handoff happened")
        expect(material).not_to include("old handoff")    # already folded
        double(structured_output: { "shared_narrative" => "v2" })
      end

      result = described_class.call

      expect(Summary.by_type("overall").count).to eq(2)
      expect(Summary.by_type("overall").recent.first.summary_text).to eq("v2")
      expect(result.data[:folded]).to eq(1)
    end
  end

  context "no new handoffs" do
    it "skips without creating an overall summary" do
      result = described_class.call
      expect(result.data[:skipped]).to be(true)
      expect(Summary.by_type("overall")).to be_empty
    end
  end
end
