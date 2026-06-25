# frozen_string_literal: true

require "rails_helper"

RSpec.describe Prompts::SystemContextEnhancer do
  describe "proactive memory recall (#build_relevant_knowledge_context)" do
    subject(:context) { enhancer.send(:build_relevant_knowledge_context) }

    let(:enhancer) { described_class.new("base context", user_message: "What's happening tonight?") }

    it "surfaces recent memories the brain can reference" do
      memory = build(:conversation_memory, summary: "User loves the fire art near the temple")
      allow(Memory::MemoryRecallService).to receive(:get_relevant_memories)
        .with(limit: 3).and_return([ memory ])

      expect(context).to include("MEMORIES YOU CAN REFERENCE")
      expect(context).to include("User loves the fire art near the temple")
    end

    it "returns nil when there are no relevant memories" do
      allow(Memory::MemoryRecallService).to receive(:get_relevant_memories).and_return([])
      expect(context).to be_nil
    end

    it "returns nil without a user message (not a system-prompt build)" do
      enhancer = described_class.new("base context", user_message: nil)
      expect(enhancer.send(:build_relevant_knowledge_context)).to be_nil
    end
  end
end
