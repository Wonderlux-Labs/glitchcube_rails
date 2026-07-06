# app/services/prompts/message_history_builder.rb
module Prompts
  class MessageHistoryBuilder
    # Soft marker inserted where the session changes, so the LLM can tell one
    # interaction from another without us hard-resetting history per conversation.
    SESSION_BREAK = "— (a separate, earlier interaction — possibly a different person) —"

    def self.build(conversation, limit: nil, since: nil)
      new(conversation: conversation, limit: limit, since: since).build
    end

    # limit / since default to the live config (see conversation_config.rb) so they
    # can be tuned from `rails c` without a code change.
    def initialize(conversation:, limit: nil, since: nil)
      @conversation = conversation
      @limit = limit || Rails.configuration.history_window_limit
      @since = since || Rails.configuration.history_window_minutes.minutes.ago
    end

    # A rolling window of the cube's most recent interactions ACROSS sessions,
    # bounded by BOTH a time window and a turn cap: recent bleed when people are
    # actively around, nothing once the cube's been idle past the window (summaries
    # will carry longer-term continuity). Ordered chronologically as user →
    # assistant per turn, with a soft break wherever the session id changes.
    def build
      return [] unless @conversation

      logs = recent_logs
      return [] if logs.empty?

      messages = []
      previous_session = nil
      logs.each do |log|
        messages << { role: "system", content: SESSION_BREAK } if previous_session && log.session_id != previous_session
        messages << { role: "user", content: log.user_message }
        messages << { role: "assistant", content: log.ai_response }
        previous_session = log.session_id
      end
      messages
    end

    private

    # Most recent turns from ALL sessions within the time window, capped, back in
    # chronological order.
    def recent_logs
      ConversationLog.where("created_at >= ?", @since)
                     .recent
                     .limit(@limit)
                     .to_a
                     .reverse
    end
  end
end
