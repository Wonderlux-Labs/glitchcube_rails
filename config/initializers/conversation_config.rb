# Configuration for ConversationNewOrchestrator system
Rails.application.configure do
  # Conversation staleness timeout - how long before a conversation is considered stale
  config.conversation_stale_timeout = 5.minutes

  # Memory search result limit
  config.memory_search_limit = 3

  # Conversation continue delay - how long to wait before re-enabling listening when continue_conversation is true
  config.conversation_continue_delay = 3.seconds

  # LLM amendment removed - query results now deferred to next conversation turn
  # config.llm_amendment_timeout = 10
  # config.llm_input_max_speech_length = 500
  # config.llm_input_max_results_length = 1000
end
