# spec/services/prompts/message_history_builder_spec.rb
require 'rails_helper'

RSpec.describe Prompts::MessageHistoryBuilder do
  let(:conversation) { create(:conversation) }

  describe '.build' do
    it 'delegates to the instance' do
      expect_any_instance_of(described_class).to receive(:build).and_return([])
      expect(described_class.build(conversation)).to eq([])
    end

    it 'passes an explicit limit through' do
      expect(described_class).to receive(:new)
        .with(conversation: conversation, limit: 5, since: nil).and_call_original
      described_class.build(conversation, limit: 5)
    end
  end

  describe '#build' do
    it 'returns [] when conversation is nil' do
      expect(described_class.new(conversation: nil).build).to eq([])
    end

    it 'returns [] when there are no recent logs' do
      expect(described_class.new(conversation: conversation).build).to eq([])
    end

    context 'with recent logs in one session' do
      before do
        create(:conversation_log, conversation: conversation, user_message: "Hello",
               ai_response: "Hi there!", created_at: 3.minutes.ago)
        create(:conversation_log, conversation: conversation, user_message: "How are you?",
               ai_response: "I'm doing great!", created_at: 2.minutes.ago)
        create(:conversation_log, conversation: conversation, user_message: "What's your name?",
               ai_response: "I'm Buddy!", created_at: 1.minute.ago)
      end

      it 'returns each turn as user then assistant, in chronological order' do
        result = described_class.new(conversation: conversation).build

        expect(result).to eq([
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hi there!" },
          { role: "user", content: "How are you?" },
          { role: "assistant", content: "I'm doing great!" },
          { role: "user", content: "What's your name?" },
          { role: "assistant", content: "I'm Buddy!" }
        ])
      end

      it 'respects an explicit turn cap (keeps the most recent)' do
        result = described_class.new(conversation: conversation, limit: 2).build
        expect(result.map { |m| m[:content] }).to eq(
          [ "How are you?", "I'm doing great!", "What's your name?", "I'm Buddy!" ]
        )
      end
    end

    context 'time window' do
      before do
        create(:conversation_log, conversation: conversation, user_message: "ancient",
               ai_response: "old reply", created_at: 30.minutes.ago)
        create(:conversation_log, conversation: conversation, user_message: "fresh",
               ai_response: "new reply", created_at: 1.minute.ago)
      end

      it 'excludes turns older than the window (default 10 min)' do
        result = described_class.new(conversation: conversation).build
        expect(result.map { |m| m[:content] }).to eq([ "fresh", "new reply" ])
      end

      it 'includes older turns if the window is widened' do
        result = described_class.new(conversation: conversation, since: 1.hour.ago).build
        expect(result.map { |m| m[:content] }).to include("ancient", "fresh")
      end
    end

    context 'default cap' do
      before do
        20.times do |i|
          create(:conversation_log, conversation: conversation, user_message: "m#{i}",
                 ai_response: "r#{i}", created_at: (20 - i).seconds.ago)
        end
      end

      it 'caps at the configured limit (8 turns = 16 messages)' do
        result = described_class.new(conversation: conversation).build
        expect(result.length).to eq(16)
      end
    end

    context 'persona scoping (no cross-persona bleed)' do
      let(:other_persona) { create(:conversation, persona: "someone_else") }

      before do
        create(:conversation_log, conversation: other_persona, user_message: "different persona",
               ai_response: "not me", created_at: 2.minutes.ago)
        create(:conversation_log, conversation: conversation, user_message: "my turn",
               ai_response: "here i am", created_at: 1.minute.ago)
      end

      it "includes only the current persona's turns" do
        result = described_class.new(conversation: conversation).build
        expect(result.map { |m| m[:content] }).to eq([ "my turn", "here i am" ])
        expect(result.map { |m| m[:content] }).not_to include("different persona")
      end
    end

    context 'across sessions of the same persona' do
      let(:other) { create(:conversation) } # same default persona ("artifact")

      before do
        create(:conversation_log, conversation: other, user_message: "im leaving",
               ai_response: "bye!", created_at: 3.minutes.ago)
        create(:conversation_log, conversation: conversation, user_message: "hi again",
               ai_response: "oh, you're back", created_at: 1.minute.ago)
      end

      it 'pulls turns from other recent sessions and marks the boundary' do
        result = described_class.new(conversation: conversation).build

        expect(result).to eq([
          { role: "user", content: "im leaving" },
          { role: "assistant", content: "bye!" },
          { role: "system", content: described_class::SESSION_BREAK },
          { role: "user", content: "hi again" },
          { role: "assistant", content: "oh, you're back" }
        ])
      end
    end
  end
end
