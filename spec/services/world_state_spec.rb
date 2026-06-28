# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorldState do
  let(:tmp_file) { Rails.root.join("tmp", "world_state_spec_#{SecureRandom.hex(4)}.md") }
  let(:fake_ha) { FakeHomeAssistant.new }

  before do
    stub_const("WorldState::FILE_PATH", tmp_file)
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
      File.write(tmp_file, "the crowd is rowdy")
      expect(described_class.current).to eq("the crowd is rowdy")
    end
  end

  describe ".replace" do
    it "writes the file as the source of truth" do
      described_class.replace("  you're the fourth person to ask that  ")
      expect(File.read(tmp_file)).to eq("you're the fourth person to ask that")
    end

    it "mirrors the content to the Home Assistant sensor" do
      described_class.replace("someone was just rude to you")
      sensor = fake_ha.entity(WorldState::SENSOR)
      expect(sensor).to be_present
      expect(sensor.dig("attributes", "content")).to eq("someone was just rude to you")
    end

    it "round-trips through .current" do
      described_class.replace("a calm night")
      expect(described_class.current).to eq("a calm night")
    end
  end
end
