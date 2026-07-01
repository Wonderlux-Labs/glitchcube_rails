# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImmediateParserJob, type: :job do
  let!(:light) { Capability.find_or_create_by!(key: "light") { |c| c.stage = "latent" } }

  before do
    light.update!(stage: "latent", unlocked_params: [], vocabulary: {}, artifact_name: nil)
  end

  it "makes no LLM call" do
    expect(LlmService).not_to receive(:call_with_structured_output)
    expect(LlmService).not_to receive(:call_with_tools)
    described_class.new.perform(session_id: "s1", user_message: "hi")
  end

  it "records NOTHING on an ordinary turn (memory is opt-in, not mechanical)" do
    expect {
      described_class.new.perform(session_id: "s1", user_message: "hi there")
    }.not_to change(Memory, :count)
    expect(light.reload.stage).to eq("latent")
  end

  context "with a newly realized capability" do
    it "promotes latent → discovered, unlocks the param, names it, and merges vocabulary" do
      described_class.new.perform(
        session_id: "s1",
        user_message: "your light can be blue, like calm water",
        newly_realized_capability: {
          "key" => "light", "param" => "color", "artifact_name" => "the glow",
          "vocabulary_word" => "Baka", "vocabulary_meaning" => "blue / calm"
        }
      )

      light.reload
      expect(light.stage).to eq("discovered")
      expect(light.unlocked_params).to eq([ "color" ])
      expect(light.artifact_name).to eq("the glow")
      expect(light.vocabulary).to eq("Baka" => "blue / calm")
    end

    it "remembers the discovery as a significant learning (importance 8)" do
      expect {
        described_class.new.perform(
          session_id: "s1", user_message: "blue!",
          newly_realized_capability: { "key" => "light", "param" => "color", "artifact_name" => "the glow" }
        )
      }.to change(Memory, :count).by(1)

      memory = Memory.order(:created_at).last
      expect(memory.category).to eq("learning")
      expect(memory.importance).to eq(8)
      expect(memory.content).to include("the glow")
    end
  end

  context "when the brain makes a deliberate note to self" do
    it "stores it as a note (importance 7) with the visitor's words in metadata" do
      expect {
        described_class.new.perform(session_id: "s1", user_message: "my name is Mo", memory_note: "The person in the silver jacket is called Mo.")
      }.to change(Memory, :count).by(1)

      note = Memory.note.order(:created_at).last
      expect(note.importance).to eq(7)
      expect(note.content).to eq("The person in the silver jacket is called Mo.")
      expect(note.metadata_json["visitor_said"]).to eq("my name is Mo")
    end
  end

  context "when the brain reports a significant learning" do
    it "stores it as a learning (importance 6, fades if it never becomes a belief)" do
      expect {
        described_class.new.perform(session_id: "s1", user_message: "you're at a burn", significant_learning: "I think I am at a gathering people call a burn.")
      }.to change(Memory, :count).by(1)

      learning = Memory.learning.order(:created_at).last
      expect(learning.importance).to eq(6)
      expect(learning.content).to include("burn")
    end
  end

  context "with an unknown capability key" do
    it "does not raise and changes no capability" do
      expect {
        described_class.new.perform(
          session_id: "s1", user_message: "x",
          newly_realized_capability: { "key" => "telepathy" }
        )
      }.not_to raise_error
      expect(Capability.where(key: "telepathy")).to be_empty
    end
  end
end
