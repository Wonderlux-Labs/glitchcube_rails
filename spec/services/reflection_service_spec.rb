# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReflectionService do
  let(:tmp_file) { Rails.root.join("tmp", "world_state_spec_#{SecureRandom.hex(4)}.md") }
  let(:fake_ha) { FakeHomeAssistant.new }

  let(:llm_result) do
    {
      "world_state" => "Three people asked about the cube's dreams tonight; the vibe is playful.",
      "summary" => "A playful evening of dream questions.",
      "memories" => [
        { "content" => "Someone is throwing a party Saturday", "category" => "event",
          "importance" => 7, "emotion" => "curious", "occurs_at" => 1.day.from_now.iso8601 },
        { "content" => "A regular named Mo keeps visiting", "category" => "person", "importance" => 6 }
      ]
    }
  end

  before do
    stub_const("WorldState::FILE_PATH", tmp_file)
    HomeAssistantService.instance = fake_ha
    allow(LlmService).to receive(:call_with_structured_output)
      .and_return(OpenStruct.new(structured_output: llm_result, content: "ok"))
  end

  after do
    File.delete(tmp_file) if File.exist?(tmp_file)
    HomeAssistantService.reset_instance!
  end

  def finished_conversation_with_logs(persona:)
    conversation = create(:conversation, persona: persona, started_at: 1.hour.ago, ended_at: 30.minutes.ago)
    create(:conversation_log, session_id: conversation.session_id,
                              user_message: "do you dream?", ai_response: "constantly, in color")
    conversation
  end

  context "with unreflected finished conversations" do
    let!(:conversations) do
      [ finished_conversation_with_logs(persona: "buddy"), finished_conversation_with_logs(persona: "jax") ]
    end

    it "rewrites the world-state from the LLM result" do
      described_class.call
      expect(WorldState.current).to include("playful")
    end

    it "mirrors the world-state to Home Assistant" do
      described_class.call
      expect(fake_ha.entity(WorldState::SENSOR)).to be_present
    end

    it "creates the flagged memories with category/emotion/occurs_at" do
      expect { described_class.call }.to change(Memory, :count).by(2)
      party = Memory.find_by(category: "event")
      expect(party.emotion).to eq("curious")
      expect(party.occurs_at).to be_present
    end

    it "archives a reflection summary" do
      expect { described_class.call }.to change { Summary.where(summary_type: "reflection").count }.by(1)
    end

    it "marks the conversations reflected" do
      described_class.call
      expect(conversations.map { |c| c.reload.reflected_at }).to all(be_present)
    end

    it "skips conversations already reflected on the next run" do
      described_class.call
      expect(LlmService).to have_received(:call_with_structured_output).once
      described_class.call # nothing new
      expect(LlmService).to have_received(:call_with_structured_output).once
    end
  end

  context "with nothing to reflect on" do
    it "is a no-op and does not call the LLM" do
      result = described_class.call
      expect(result.success?).to be(true)
      expect(result.data[:reflected]).to eq(0)
      expect(LlmService).not_to have_received(:call_with_structured_output)
    end
  end
end
