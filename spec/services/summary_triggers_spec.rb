# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SummaryTriggers do
  let!(:neon) { Persona.create!(slug: "neon", name: "Neon") }
  let(:convo) { create(:conversation, persona: "neon") }

  def add_turns(n, at: Time.current)
    n.times { |i| create(:conversation_log, conversation: convo, user_message: "u#{i}", ai_response: "a#{i}", created_at: at + i.seconds) }
  end

  it "enqueues a chunk exactly on the Nth unsummarized turn" do
    add_turns(described_class::CHUNK_EVERY)
    expect(Recurring::Memory::SummarizerJob).to receive(:perform_later).with("neon")
    described_class.after_turn("neon")
  end

  it "does not enqueue before N turns" do
    add_turns(described_class::CHUNK_EVERY - 1)
    expect(Recurring::Memory::SummarizerJob).not_to receive(:perform_later)
    described_class.after_turn("neon")
  end

  it "does not re-enqueue on the turns between multiples of N" do
    add_turns(described_class::CHUNK_EVERY + 1) # one past the boundary
    expect(Recurring::Memory::SummarizerJob).not_to receive(:perform_later)
    described_class.after_turn("neon")
  end

  it "counts only turns since this persona's last chunk" do
    create(:summary, summary_type: "interaction", persona: neon, end_time: 1.minute.ago)
    add_turns(described_class::CHUNK_EVERY, at: Time.current) # all after the chunk
    expect(Recurring::Memory::SummarizerJob).to receive(:perform_later).with("neon")
    described_class.after_turn("neon")
  end

  it "does not enqueue a persona fold (fold is switch-only)" do
    add_turns(60)
    expect(PersonaSummarizerJob).not_to receive(:perform_later)
    allow(Recurring::Memory::SummarizerJob).to receive(:perform_later)
    described_class.after_turn("neon")
  end

  it "no-ops for a blank or unknown persona" do
    expect { described_class.after_turn(nil) }.not_to raise_error
    expect { described_class.after_turn("nobody") }.not_to raise_error
  end
end
