# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArtifactDecayService do
  describe ".call" do
    it "decays self beliefs by 2 and world beliefs by 1, flooring at 0" do
      self_belief  = Belief.create!(statement: "I am a probe", category: "self", confidence: 5)
      world_belief = Belief.create!(statement: "This is a burn", category: "world", confidence: 5)
      low_self     = Belief.create!(statement: "I am tired", category: "self", confidence: 1)

      described_class.call

      expect(self_belief.reload.confidence).to eq(3)
      expect(world_belief.reload.confidence).to eq(4)
      expect(Belief.exists?(low_self.id)).to be(false) # 1 - 2 floored to 0, then forgotten
    end

    it "leaves locked beliefs untouched" do
      locked = Belief.create!(statement: "My name is Echo", category: "self", confidence: 10, locked: true)
      described_class.call
      expect(locked.reload.confidence).to eq(10)
    end

    it "forgets (deletes) beliefs that reach 0" do
      dying = Belief.create!(statement: "I am from Mars", category: "world", confidence: 1)
      described_class.call
      expect(Belief.exists?(dying.id)).to be(false)
    end

    it "prunes mundane old memories but keeps significant and recent ones" do
      old_mundane = Memory.create!(content: "old chatter", category: "interaction", importance: 3, created_at: 2.days.ago)
      old_significant = Memory.create!(content: "a discovery", category: "interaction", importance: 8, created_at: 2.days.ago)
      recent_mundane = Memory.create!(content: "recent chatter", category: "interaction", importance: 3, created_at: 1.hour.ago)

      described_class.call

      expect(Memory.exists?(old_mundane.id)).to be(false)
      expect(Memory.exists?(old_significant.id)).to be(true)
      expect(Memory.exists?(recent_mundane.id)).to be(true)
    end

    it "returns a success ServiceResult with counts" do
      Belief.create!(statement: "I am a probe", category: "self", confidence: 5)
      result = described_class.call
      expect(result.success?).to be(true)
      expect(result.data).to include(:decayed, :forgotten, :pruned)
    end
  end
end
