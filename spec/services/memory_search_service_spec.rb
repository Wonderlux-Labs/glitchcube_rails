# frozen_string_literal: true

require "rails_helper"

RSpec.describe MemorySearchService do
  subject(:service) { described_class.new }

  let!(:storm) { create(:memory, category: "fact", content: "A bad storm rolled through last night") }
  let!(:burn)  { create(:memory, :event, content: "Effigy burn", occurs_at: 1.day.from_now.change(hour: 22)) }

  it "finds memories by keyword" do
    result = service.call(query: "storm")
    expect(result[:success]).to be(true)
    expect(result[:results].map { |m| m[:content] }).to include(storm.content)
  end

  it "filters by category" do
    result = service.call(category: "event")
    expect(result[:results].map { |m| m[:content] }).to contain_exactly(burn.content)
  end

  it "finds events happening tomorrow via timeframe" do
    result = service.call(category: "event", timeframe: "tomorrow")
    expect(result[:results].map { |m| m[:content] }).to contain_exactly(burn.content)
  end

  it "errors when given no criteria" do
    expect(service.call[:success]).to be(false)
  end

  it "reports zero results gracefully" do
    result = service.call(query: "nonexistent zzzzz")
    expect(result[:success]).to be(true)
    expect(result[:total_results]).to eq(0)
  end
end
