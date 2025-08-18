# frozen_string_literal: true

FactoryBot.define do
  factory :conversation_memory do
    association :conversation
    session_id { conversation&.session_id || SecureRandom.uuid }
    summary { 'User prefers concise responses' }
    memory_type { 'preference' }
    importance { 5 }
    metadata { '{"context": "conversation"}' }
  end
end