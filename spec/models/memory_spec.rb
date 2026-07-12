# frozen_string_literal: true

require "rails_helper"

RSpec.describe Memory, type: :model do
  describe "validations" do
    it "is valid with content, category, importance" do
      expect(build(:memory)).to be_valid
    end

    it "requires content" do
      expect(build(:memory, content: nil)).not_to be_valid
    end

    it "rejects categories outside the enum" do
      expect(build(:memory, category: "nonsense")).not_to be_valid
    end

    it "rejects importance outside 1..10" do
      expect(build(:memory, importance: 0)).not_to be_valid
      expect(build(:memory, importance: 11)).not_to be_valid
    end

    # Embeddings/pgvector removed in this version — the `embedding` column no
    # longer exists. Restore this (and the column) if vector search comes back.
    # it "does not embed on save (no vectorsearch hook)" do
    #   memory = create(:memory)
    #   expect(memory.embedding).to be_nil
    #   expect(Memory._save_callbacks.map(&:filter)).not_to include(:upsert_to_vectorsearch)
    # end
  end

  describe ".search" do
    let!(:storm)  { create(:memory, category: "fact", content: "There was a bad storm last night", importance: 6) }
    let!(:snack)  { create(:memory, category: "preference", content: "They love spicy snacks", importance: 4) }
    let!(:burn)   { create(:memory, :event, content: "Effigy burn", occurs_at: 1.day.from_now.change(hour: 22)) }
    let!(:past)   { create(:memory, :event, content: "Old ritual", occurs_at: 2.days.ago) }

    it "matches by keyword in content" do
      expect(Memory.search(query: "storm")).to contain_exactly(storm)
    end

    it "filters by category" do
      expect(Memory.search(category: "event")).to match_array([ burn, past ])
    end

    it "returns memories occurring tomorrow with a timeframe window" do
      window = { on_or_after: 1.day.from_now.beginning_of_day, on_or_before: 1.day.from_now.end_of_day }
      expect(Memory.search(**window)).to contain_exactly(burn)
    end

    it "orders plain searches by importance" do
      results = Memory.search(limit: 10)
      expect(results.first.importance).to be >= results.last.importance
    end

    it "respects the limit" do
      expect(Memory.search(limit: 1).size).to eq(1)
    end
  end
end
