# frozen_string_literal: true

FactoryBot.define do
  factory :conversation do
    session_id { SecureRandom.uuid }
    persona { 'default' }
    source { 'api' }
    started_at { Time.current }
    message_count { 0 }
    total_cost { 0.0 }
    total_tokens { 0 }
    continue_conversation { true }

    trait :with_conversation_logs do
      after(:create) do |conversation|
        create_list(:conversation_log, 3, conversation: conversation)
      end
    end
  end
end
