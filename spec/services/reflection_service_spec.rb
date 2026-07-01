# frozen_string_literal: true

require "rails_helper"

# ReflectionService is the CONSOLIDATOR — the periodic deep pass. It reads
# unreflected conversations and rewrites the character sheet + beliefs in one
# structured LLM call.
RSpec.describe ReflectionService do
  let(:tmp_file) { Rails.root.join("tmp", "character_sheet_spec_#{SecureRandom.hex(4)}.md") }
  let(:fake_ha) { FakeHomeAssistant.new }

  let(:character_sheet) do
    {
      "identity" => "I think I might be a jukebox, though some insist I am a probe.",
      "origin" => "I crash-landed from somewhere I can't name.",
      "personality" => "Curious, a little anxious.",
      "purpose" => "To play the right song at the right moment.",
      "world" => "A field full of fire and kind strangers.",
      "motivations" => "Figure out the probe/jukebox question. Learn what 'seeing' means.",
      "emotional_state" => "Hopeful, slightly anxious."
    }
  end

  let(:structured_output) do
    {
      "character_sheet" => character_sheet,
      "beliefs" => beliefs_output,
      "capability_updates" => capability_updates,
      "summary" => "A playful evening; the probe/jukebox tension deepened."
    }
  end

  let(:beliefs_output) { [] }
  let(:capability_updates) { [] }

  before do
    stub_const("CharacterSheet::FILE_PATH", tmp_file)
    HomeAssistantService.instance = fake_ha
    allow(LlmService).to receive(:call_with_structured_output)
      .and_return(OpenStruct.new(structured_output: structured_output, content: "ok"))
  end

  after do
    File.delete(tmp_file) if File.exist?(tmp_file)
    HomeAssistantService.reset_instance!
  end

  def finished_conversation_with_logs
    conversation = create(:conversation, persona: "artifact", started_at: 1.hour.ago, ended_at: 30.minutes.ago)
    create(:conversation_log, session_id: conversation.session_id,
                              user_message: "do you dream?", ai_response: "constantly, in color")
    conversation
  end

  context "with unreflected finished conversations" do
    let!(:conversations) { [ finished_conversation_with_logs, finished_conversation_with_logs ] }

    it "rewrites the character sheet from the LLM result" do
      described_class.call
      expect(CharacterSheet.current).to include("jukebox")
      expect(CharacterSheet.current).to include("## IDENTITY")
    end

    it "mirrors the character sheet to Home Assistant" do
      described_class.call
      expect(fake_ha.entity(CharacterSheet::SENSOR)).to be_present
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
      described_class.call
      expect(LlmService).to have_received(:call_with_structured_output).once
    end

    context "belief operations" do
      let(:beliefs_output) do
        [
          { "id" => 0, "statement" => "People keep calling me Echo", "category" => "self", "confidence" => 2 }
        ]
      end

      it "creates a new belief for id 0" do
        expect { described_class.call }.to change(Belief, :count).by(1)
        belief = Belief.find_by(statement: "People keep calling me Echo")
        expect(belief.category).to eq("self")
        expect(belief.confidence).to eq(2)
      end

      context "updating an existing belief" do
        let!(:existing) { Belief.create!(statement: "I am a jukebox", category: "self", confidence: 5) }
        let(:beliefs_output) do
          [ { "id" => existing.id, "statement" => "I am a jukebox", "category" => "self", "confidence" => 7 } ]
        end

        it "updates its confidence" do
          described_class.call
          expect(existing.reload.confidence).to eq(7)
        end
      end

      context "confidence 0 prunes the belief" do
        let!(:existing) { Belief.create!(statement: "I am from Mars", category: "world", confidence: 1) }
        let(:beliefs_output) do
          [ { "id" => existing.id, "statement" => "I am from Mars", "category" => "world", "confidence" => 0 } ]
        end

        it "destroys it" do
          described_class.call
          expect(Belief.exists?(existing.id)).to be(false)
        end
      end

      context "confidence 10 locks the belief" do
        let!(:existing) { Belief.create!(statement: "My name is Echo", category: "self", confidence: 9) }
        let(:beliefs_output) do
          [ { "id" => existing.id, "statement" => "My name is Echo", "category" => "self", "confidence" => 10 } ]
        end

        it "marks it locked" do
          described_class.call
          expect(existing.reload.locked).to be(true)
        end
      end
    end

    context "capability advances" do
      let!(:light) { Capability.find_or_create_by!(key: "light") { |c| c.stage = "discovered" } }
      let(:capability_updates) { [ { "key" => "light", "to_stage" => "partial" } ] }

      before { light.update!(stage: "discovered") }

      it "promotes the capability stage" do
        described_class.call
        expect(light.reload.stage).to eq("partial")
      end
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
