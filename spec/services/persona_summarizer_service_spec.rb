# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PersonaSummarizerService do
  let!(:zorp) { Persona.create!(slug: "zorp", name: "Zorp") }

  def stub_llm(summary:, ooc_note: nil)
    payload = { "summary" => summary }
    payload["ooc_note"] = ooc_note unless ooc_note.nil?
    allow(LlmService).to receive(:call_with_structured_output)
      .and_return(double(structured_output: payload))
  end

  def convo_with_logs(persona_slug:, prefix:, count: 2, at: 2.minutes.ago)
    convo = create(:conversation, persona: persona_slug)
    count.times do |i|
      create(:conversation_log, conversation: convo,
             user_message: "#{prefix}-u#{i}", ai_response: "#{prefix}-a#{i}", created_at: at + i.seconds)
    end
    convo
  end

  context "first run" do
    before do
      convo_with_logs(persona_slug: "zorp", prefix: "ZORP", at: 2.minutes.ago)
      convo_with_logs(persona_slug: "buddy", prefix: "BUDDY", at: 2.minutes.ago) # different persona — must be excluded
    end

    it "writes a versioned persona summary from ONLY that persona's conversations" do
      stub_llm(summary: "You leaned cosmic and did some readings.")

      result = described_class.call("zorp")

      expect(result.success?).to be(true)
      s = zorp.summaries.where(summary_type: "persona").last
      expect(s.summary_text).to eq("You leaned cosmic and did some readings.")
      expect(s.persona).to eq(zorp)
      expect(s.message_count).to eq(2) # zorp's 2 logs only, not buddy's
    end

    it "feeds only this persona's logs into the material" do
      expect(LlmService).to receive(:call_with_structured_output) do |args|
        material = args[:messages].last[:content]
        expect(material).to include("ZORP-u0")
        expect(material).not_to include("BUDDY")
        double(structured_output: { "summary" => "ok" })
      end
      described_class.call("zorp")
    end

    it "stores a self-steering ooc_note when present" do
      stub_llm(summary: "cosmic night", ooc_note: "You keep leaning on the butt-reading bit — vary it.")
      described_class.call("zorp")
      expect(zorp.summaries.where(summary_type: "persona").last.metadata_json["ooc_note"])
        .to eq("You keep leaning on the butt-reading bit — vary it.")
    end
  end

  context "subsequent run — versioned + boundary" do
    it "creates a new version, folding its prior self and only newer conversations" do
      convo_with_logs(persona_slug: "zorp", prefix: "OLD", at: 20.minutes.ago)
      stub_llm(summary: "v1")
      described_class.call("zorp")
      expect(zorp.summaries.where(summary_type: "persona").last.summary_text).to eq("v1")

      convo_with_logs(persona_slug: "zorp", prefix: "NEW", at: 1.minute.ago)

      expect(LlmService).to receive(:call_with_structured_output) do |args|
        material = args[:messages].last[:content]
        expect(material).to include("v1")   # prior self-summary handed back in
        expect(material).to include("NEW")
        expect(material).not_to include("OLD") # already folded
        double(structured_output: { "summary" => "v2" })
      end

      described_class.call("zorp")

      persona_summaries = zorp.summaries.where(summary_type: "persona").order(:created_at)
      expect(persona_summaries.count).to eq(2)          # versioned
      expect(persona_summaries.last.summary_text).to eq("v2")
    end
  end

  it "skips when the persona had no conversations" do
    result = described_class.call("zorp")
    expect(result.data[:skipped]).to be(true)
    expect(zorp.summaries.where(summary_type: "persona")).to be_empty
  end

  it "fails for an unknown persona" do
    expect(described_class.call("nobody").success?).to be(false)
  end
end
