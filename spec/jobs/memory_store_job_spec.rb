# frozen_string_literal: true

require "rails_helper"

RSpec.describe MemoryStoreJob, type: :job do
  let(:session_id) { "mem_job_session" }

  # ConversationMemory belongs_to :conversation via session_id.
  before { create(:conversation, session_id: session_id) }

  it "persists each flagged memory as a ConversationMemory" do
    memories = [
      { "summary" => "User's name is Dot", "memory_type" => "fact", "importance" => 8 },
      { "summary" => "Prefers quiet music", "memory_type" => "preference", "importance" => 6 }
    ]

    expect {
      described_class.perform_now(session_id: session_id, memories: memories)
    }.to change(ConversationMemory, :count).by(2)

    stored = ConversationMemory.where(session_id: session_id).order(:importance)
    expect(stored.map(&:summary)).to contain_exactly("User's name is Dot", "Prefers quiet music")
    expect(stored.find_by(summary: "User's name is Dot")).to have_attributes(memory_type: "fact", importance: 8)
  end

  it "skips entries with a blank summary" do
    memories = [ { "summary" => "  ", "memory_type" => "fact" }, { "summary" => "Real fact" } ]

    expect {
      described_class.perform_now(session_id: session_id, memories: memories)
    }.to change(ConversationMemory, :count).by(1)
  end

  it "normalizes untrusted LLM values into the model's valid ranges" do
    memories = [ { "summary" => "Edge case", "memory_type" => "nonsense", "importance" => 99 } ]

    described_class.perform_now(session_id: session_id, memories: memories)

    memory = ConversationMemory.find_by(summary: "Edge case")
    expect(memory.memory_type).to eq("fact")    # unknown type falls back to fact
    expect(memory.importance).to eq(10)         # clamped into 1..10
  end

  it "defaults memory_type and importance when omitted" do
    described_class.perform_now(session_id: session_id, memories: [ { "summary" => "Bare fact" } ])

    memory = ConversationMemory.find_by(summary: "Bare fact")
    expect(memory.memory_type).to eq("fact")
    expect(memory.importance).to eq(5)
  end
end
