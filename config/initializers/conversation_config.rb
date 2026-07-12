# Configuration for ConversationOrchestrator system
Rails.application.configure do
  # Conversation staleness timeout - how long before a conversation is considered stale
  config.conversation_stale_timeout = 5.minutes

  # Memory search result limit
  config.memory_search_limit = 3

  # Conversation history window (message bleed across sessions). Read at call time
  # by Prompts::MessageHistoryBuilder, so both are adjustable live from `rails c`
  # (e.g. `Rails.application.config.history_window_limit = 8`).
  #   minutes — only pull turns from the last N minutes (so a cube idle for 20 min
  #             starts fresh rather than dredging up an unrelated interaction)
  #   limit   — hard cap on how many recent turns to include
  # Kept in step with SummaryTriggers::CHUNK_EVERY (8): the raw window carries the last ~8
  # turns live, and every 8 turns those get captured into an interaction chunk — so as a turn
  # ages out of the raw window it's already preserved in the current-session chunk record.
  config.history_window_minutes = Integer(ENV.fetch("HISTORY_WINDOW_MINUTES", 10))
  config.history_window_limit = Integer(ENV.fetch("HISTORY_WINDOW_LIMIT", 8))

  # Conversation continue delay - how long to wait before re-enabling listening when continue_conversation is true
  config.conversation_continue_delay = 3.seconds

  # LLM amendment removed - query results now deferred to next conversation turn
  # config.llm_amendment_timeout = 10
  # config.llm_input_max_speech_length = 500
  # config.llm_input_max_results_length = 1000
end
