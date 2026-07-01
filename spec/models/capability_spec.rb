# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capability, type: :model do
  describe "validations" do
    it "requires a key" do
      expect(Capability.new(stage: "latent")).not_to be_valid
    end

    it "requires a unique key" do
      Capability.create!(key: "light", stage: "latent")
      dup = Capability.new(key: "light", stage: "latent")
      expect(dup).not_to be_valid
      expect(dup.errors[:key]).to be_present
    end

    it "requires a stage in STAGES" do
      expect(Capability.new(key: "x", stage: "bogus")).not_to be_valid
      expect(Capability.new(key: "x", stage: "discovered")).to be_valid
    end
  end

  describe "scopes" do
    let!(:latent)  { Capability.create!(key: "sight", stage: "latent") }
    let!(:found)   { Capability.create!(key: "light", stage: "discovered") }

    it "unlocked excludes latent" do
      expect(Capability.unlocked).to contain_exactly(found)
    end

    it "still_latent returns latent only" do
      expect(Capability.still_latent).to contain_exactly(latent)
    end
  end

  describe "#unlocked?" do
    it "is false when latent, true otherwise" do
      expect(Capability.new(key: "x", stage: "latent").unlocked?).to be(false)
      expect(Capability.new(key: "x", stage: "partial").unlocked?).to be(true)
    end
  end

  describe "#promote!" do
    it "advances one stage by default" do
      cap = Capability.create!(key: "light", stage: "latent")
      cap.promote!
      expect(cap.stage).to eq("discovered")
    end

    it "advances to a named further stage" do
      cap = Capability.create!(key: "light", stage: "discovered")
      cap.promote!(to: "mastered")
      expect(cap.stage).to eq("mastered")
    end

    it "never downgrades" do
      cap = Capability.create!(key: "light", stage: "partial")
      cap.promote!(to: "discovered")
      expect(cap.reload.stage).to eq("partial")
    end
  end

  describe "#unlock_param!" do
    it "adds a unique param" do
      cap = Capability.create!(key: "light", stage: "discovered", unlocked_params: [])
      cap.unlock_param!("color")
      cap.unlock_param!("color")
      cap.unlock_param!("brightness")
      expect(cap.unlocked_params).to eq([ "color", "brightness" ])
    end

    it "ignores blank params" do
      cap = Capability.create!(key: "light", stage: "discovered", unlocked_params: [])
      cap.unlock_param!("")
      expect(cap.unlocked_params).to eq([])
    end
  end

  describe "#merge_vocabulary!" do
    it "merges add-only and ignores blank entries" do
      cap = Capability.create!(key: "light", stage: "discovered", vocabulary: { "Baka" => "blue/calm" })
      cap.merge_vocabulary!("Raka" => "red/urgent", "" => "junk", "Naka" => "")
      expect(cap.vocabulary).to eq("Baka" => "blue/calm", "Raka" => "red/urgent")
    end

    it "overwrites an explicitly re-defined word but keeps the rest" do
      cap = Capability.create!(key: "light", stage: "discovered", vocabulary: { "Baka" => "blue" })
      cap.merge_vocabulary!("Baka" => "deep blue, like calm water")
      expect(cap.vocabulary["Baka"]).to eq("deep blue, like calm water")
    end
  end
end
