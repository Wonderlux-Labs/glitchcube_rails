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

    # A rolling window of the CURRENT PERSONA's most recent interactions, bounded by
    # both a time window and a turn cap. Scoped to the current persona so raw history
    # never bleeds one character's voice into another — on a persona switch this is
    # naturally empty (that persona hasn't spoken in the window), and cross-persona
    # continuity comes from the summaries, not raw transcripts. Ordered user →
    # assistant per turn, with a soft break wherever the session id (visitor) changes.
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

    # Most recent turns of the CURRENT PERSONA within the time window, capped, back in
    # chronological order. Scoped by persona (via the conversation) so another
    # character's transcript never bleeds into this one.
    def recent_logs
      persona = @conversation.persona
      return [] if persona.blank?

      ConversationLog.joins(:conversation)
                     .where(conversations: { persona: persona })
                     .where("conversation_logs.created_at >= ?", @since)
                     .order("conversation_logs.created_at DESC")
                     .limit(@limit)
                     .to_a
                     .reverse
    end
  end
end
