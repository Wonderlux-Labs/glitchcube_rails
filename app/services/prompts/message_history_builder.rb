# app/services/prompts/message_history_builder.rb
module Prompts
  class MessageHistoryBuilder
    def self.build(conversation, limit: 10)
      new(conversation: conversation, limit: limit).build
    end

    def initialize(conversation:, limit: 10)
      @conversation = conversation
      @limit = limit
    end

    def build
      return [] unless @conversation

      @conversation.conversation_logs
                   .recent
                   .limit(@limit)
                   .flat_map { |log| format_message(log) }
                   .reverse
    end

    private

    def format_message(log)
      [
        { role: "user", content: log.user_message },
        { role: "assistant", content: log.ai_response }
      ]
    end
  end
end
