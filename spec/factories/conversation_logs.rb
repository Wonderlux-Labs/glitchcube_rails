# frozen_string_literal: true

FactoryBot.define do
  factory :conversation_log do
    transient do
      session_id { SecureRandom.uuid }
    end
    
    conversation { Conversation.find_or_create_by(session_id: session_id) }
    user_message { 'Hello, how can you help me?' }
    ai_response { 'I can help you with many things!' }
    tool_results { '{"tools_used": []}' }
    metadata { '{"source": "test"}' }
    
    after(:build) do |log, evaluator|
      log.session_id = evaluator.session_id
    end
  end
end