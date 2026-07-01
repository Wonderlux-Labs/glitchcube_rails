# frozen_string_literal: true

require "rails_helper"

RSpec.describe Belief, type: :model do
  describe "validations" do
    it "requires a statement" do
      belief = Belief.new(category: "self", confidence: 3)
      expect(belief).not_to be_valid
      expect(belief.errors[:statement]).to be_present
    end

    it "requires a category in self/world" do
      expect(Belief.new(statement: "x", category: "self", confidence: 1)).to be_valid
      expect(Belief.new(statement: "x", category: "world", confidence: 1)).to be_valid
      expect(Belief.new(statement: "x", category: "nonsense", confidence: 1)).not_to be_valid
    end

    it "requires confidence within 0..10" do
      expect(Belief.new(statement: "x", category: "self", confidence: 0)).to be_valid
      expect(Belief.new(statement: "x", category: "self", confidence: 10)).to be_valid
      expect(Belief.new(statement: "x", category: "self", confidence: 11)).not_to be_valid
      expect(Belief.new(statement: "x", category: "self", confidence: -1)).not_to be_valid
    end
  end

  describe "scopes" do
    let!(:self_strong) { Belief.create!(statement: "I am a jukebox", category: "self", confidence: 8) }
    let!(:self_weak)   { Belief.create!(statement: "I am from Mars", category: "self", confidence: 0) }
    let!(:world_one)   { Belief.create!(statement: "This is a burn", category: "world", confidence: 5) }
    let!(:locked_one)  { Belief.create!(statement: "My name is Echo", category: "self", confidence: 10, locked: true) }

    it "self_beliefs / world_beliefs split by category" do
      expect(Belief.self_beliefs).to include(self_strong, self_weak, locked_one)
      expect(Belief.self_beliefs).not_to include(world_one)
      expect(Belief.world_beliefs).to contain_exactly(world_one)
    end

    it "active excludes confidence 0" do
      expect(Belief.active).to include(self_strong, world_one, locked_one)
      expect(Belief.active).not_to include(self_weak)
    end

    it "locked returns locked beliefs" do
      expect(Belief.locked).to contain_exactly(locked_one)
    end

    it "strongest orders by confidence desc" do
      expect(Belief.strongest.first).to eq(locked_one)
    end
  end

  describe "#reinforce!" do
    it "raises confidence and caps at 10, locking on reach" do
      belief = Belief.create!(statement: "x", category: "self", confidence: 5)
      belief.reinforce!(2)
      expect(belief.confidence).to eq(7)
      expect(belief.locked).to be(false)

      belief.reinforce!(9)
      expect(belief.confidence).to eq(10)
      expect(belief.locked).to be(true)
    end
  end

  describe "#weaken!" do
    it "lowers confidence and floors at 0" do
      belief = Belief.create!(statement: "x", category: "world", confidence: 2)
      belief.weaken!(1)
      expect(belief.confidence).to eq(1)
      belief.weaken!(5)
      expect(belief.confidence).to eq(0)
    end

    it "is a no-op on locked beliefs" do
      belief = Belief.create!(statement: "x", category: "self", confidence: 10, locked: true)
      belief.weaken!(3)
      expect(belief.reload.confidence).to eq(10)
    end
  end

  describe "#lock!" do
    it "locks and pins confidence to 10" do
      belief = Belief.create!(statement: "x", category: "self", confidence: 4)
      belief.lock!
      expect(belief.locked).to be(true)
      expect(belief.confidence).to eq(10)
    end
  end
end
