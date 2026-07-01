# frozen_string_literal: true

require "rails_helper"

RSpec.describe CharacterSheet do
  let(:tmp_file) { Rails.root.join("tmp", "character_sheet_spec_#{SecureRandom.hex(4)}.md") }
  let(:fake_ha) { FakeHomeAssistant.new }

  before do
    stub_const("CharacterSheet::FILE_PATH", tmp_file)
    HomeAssistantService.instance = fake_ha
  end

  after do
    File.delete(tmp_file) if File.exist?(tmp_file)
    HomeAssistantService.reset_instance! if HomeAssistantService.respond_to?(:reset_instance!)
  end

  describe ".current" do
    it "returns empty string when no file exists" do
      expect(described_class.current).to eq("")
    end

    it "returns the file contents when present" do
      File.write(tmp_file, "I think I am a jukebox")
      expect(described_class.current).to eq("I think I am a jukebox")
    end
  end

  describe ".replace" do
    it "writes the trimmed file as the source of truth" do
      described_class.replace("  I might be from somewhere else  ")
      expect(File.read(tmp_file)).to eq("I might be from somewhere else")
    end

    it "mirrors the content to the Home Assistant sensor" do
      described_class.replace("a confused, glowing cube")
      sensor = fake_ha.entity(CharacterSheet::SENSOR)
      expect(sensor).to be_present
      expect(sensor.dig("attributes", "content")).to eq("a confused, glowing cube")
    end

    it "round-trips through .current" do
      described_class.replace("becoming something")
      expect(described_class.current).to eq("becoming something")
    end
  end

  describe ".render" do
    it "renders sections as markdown in SECTIONS order, skipping blanks" do
      md = described_class.render(
        "personality" => "Curious and a little sad.",
        "identity" => "Maybe a probe, maybe a jukebox.",
        "purpose" => ""
      )
      expect(md).to eq("## IDENTITY\nMaybe a probe, maybe a jukebox.\n\n## PERSONALITY\nCurious and a little sad.")
    end

    it "turns underscored section keys into spaced headers" do
      md = described_class.render("emotional_state" => "Hopeful, slightly anxious.")
      expect(md).to include("## EMOTIONAL STATE\nHopeful, slightly anxious.")
    end
  end
end
