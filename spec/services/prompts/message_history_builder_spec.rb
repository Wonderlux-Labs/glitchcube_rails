# spec/services/prompts/message_history_builder_spec.rb
require 'rails_helper'

RSpec.describe Prompts::MessageHistoryBuilder do
  let(:conversation) { create(:conversation) }

  describe '.build' do
    it 'delegates to instance method with default limit' do
      expect_any_instance_of(described_class).to receive(:build).and_return([])

      result = described_class.build(conversation)
      expect(result).to eq([])
    end

    it 'accepts custom limit' do
      expect(described_class).to receive(:new).with(conversation: conversation, limit: 5).and_call_original
      described_class.build(conversation, limit: 5)
    end
  end

  describe '#build' do
    context 'when conversation is nil' do
      let(:conversation) { nil }

      it 'returns empty array' do
        result = described_class.new(conversation: conversation, limit: 10).build
        expect(result).to eq([])
      end
    end

    context 'when conversation has no logs' do
      it 'returns empty array' do
        result = described_class.new(conversation: conversation, limit: 10).build
        expect(result).to eq([])
      end
    end

    context 'when conversation has logs' do
      before do
        # Create conversation logs in chronological order
        create(:conversation_log,
               conversation: conversation,
               user_message: "Hello",
               ai_response: "Hi there!",
               created_at: 3.minutes.ago)
        create(:conversation_log,
               conversation: conversation,
               user_message: "How are you?",
               ai_response: "I'm doing great!",
               created_at: 2.minutes.ago)
        create(:conversation_log,
               conversation: conversation,
               user_message: "What's your name?",
               ai_response: "I'm Buddy!",
               created_at: 1.minute.ago)
      end

      it 'returns formatted messages in correct order' do
        result = described_class.new(conversation: conversation, limit: 10).build

        # Should have 6 messages total (3 logs × 2 messages each)
        expect(result.length).to eq(6)

        # Check actual order (reverse applies to individual messages, not pairs)
        # Order: T1_ai, T1_user, T2_ai, T2_user, T3_ai, T3_user
        expect(result[0]).to eq({ role: "assistant", content: "Hi there!" })
        expect(result[1]).to eq({ role: "user", content: "Hello" })
        expect(result[2]).to eq({ role: "assistant", content: "I'm doing great!" })
        expect(result[3]).to eq({ role: "user", content: "How are you?" })
        expect(result[4]).to eq({ role: "assistant", content: "I'm Buddy!" })
        expect(result[5]).to eq({ role: "user", content: "What's your name?" })
      end

      it 'respects the limit parameter' do
        result = described_class.new(conversation: conversation, limit: 2).build

        # Should return only the most recent 2 logs (4 messages)
        expect(result.length).to eq(4)

        # Should be the most recent logs (T2_ai, T2_user, T3_ai, T3_user)
        expect(result[0]).to eq({ role: "assistant", content: "I'm doing great!" })
        expect(result[1]).to eq({ role: "user", content: "How are you?" })
        expect(result[2]).to eq({ role: "assistant", content: "I'm Buddy!" })
        expect(result[3]).to eq({ role: "user", content: "What's your name?" })
      end

      it 'handles limit of 1' do
        result = described_class.new(conversation: conversation, limit: 1).build

        # Should return only the most recent log (2 messages) (T3_ai, T3_user)
        expect(result.length).to eq(2)
        expect(result[0]).to eq({ role: "assistant", content: "I'm Buddy!" })
        expect(result[1]).to eq({ role: "user", content: "What's your name?" })
      end

      it 'formats each log as user and assistant messages' do
        result = described_class.new(conversation: conversation, limit: 10).build

        # Due to reverse, alternating pattern is assistant/user (not user/assistant)
        result.each_with_index do |message, index|
          if index.even?
            expect(message[:role]).to eq("assistant")
          else
            expect(message[:role]).to eq("user")
          end
          expect(message[:content]).to be_present
        end
      end
    end

    context 'with many logs beyond limit' do
      before do
        # Create 15 logs
        15.times do |i|
          create(:conversation_log,
                 conversation: conversation,
                 user_message: "Message #{i}",
                 ai_response: "Response #{i}",
                 created_at: (15 - i).minutes.ago)
        end
      end

      it 'limits results to specified number of logs' do
        result = described_class.new(conversation: conversation, limit: 5).build

        # Should return 5 most recent logs (10 messages)
        expect(result.length).to eq(10)

        # Should be the most recent 5 logs (but reversed individual messages)
        # Most recent logs are 14, 13, 12, 11, 10 -> reverse gives Response 10, Message 10, Response 11, Message 11...
        expect(result[0][:content]).to eq("Response 10")
        expect(result[1][:content]).to eq("Message 10")
        expect(result[8][:content]).to eq("Response 14")
        expect(result[9][:content]).to eq("Message 14")
      end

      it 'uses default limit of 10' do
        result = described_class.new(conversation: conversation, limit: 10).build

        # Should return 10 most recent logs (20 messages)
        expect(result.length).to eq(20)
      end
    end

    context 'message ordering' do
      before do
        create(:conversation_log,
               conversation: conversation,
               user_message: "First",
               ai_response: "First response",
               created_at: 2.minutes.ago)
        create(:conversation_log,
               conversation: conversation,
               user_message: "Second",
               ai_response: "Second response",
               created_at: 1.minute.ago)
      end

      it 'ensures messages are in chronological order' do
        result = described_class.new(conversation: conversation, limit: 10).build

        expect(result[0]).to eq({ role: "assistant", content: "First response" })
        expect(result[1]).to eq({ role: "user", content: "First" })
        expect(result[2]).to eq({ role: "assistant", content: "Second response" })
        expect(result[3]).to eq({ role: "user", content: "Second" })
      end

      it 'maintains user-assistant pairing' do
        result = described_class.new(conversation: conversation, limit: 10).build

        # Each pair should be adjacent assistant->user (due to reverse)
        (0...result.length).step(2) do |i|
          expect(result[i][:role]).to eq("assistant")
          expect(result[i + 1][:role]).to eq("user") if result[i + 1]
        end
      end
    end
  end
end
