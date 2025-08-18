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
  end
end