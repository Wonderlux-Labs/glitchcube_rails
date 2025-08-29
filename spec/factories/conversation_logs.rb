# frozen_string_literal: true

FactoryBot.define do
  factory :conversation_log do
    association :conversation, factory: :conversation
    user_message { 'Hello, how can you help me?' }
    ai_response { 'I can help you with many things!' }
    tool_results { '{"tools_used": []}' }
    metadata { '{"source": "test"}' }

    after(:build) do |log|
      log.session_id = log.conversation.session_id if log.conversation
    end
  end
end
