# frozen_string_literal: true

FactoryBot.define do
  factory :message do
    association :conversation
    role { 'user' }
    content { 'This is a test message' }
    model_used { 'gpt-4' }
    prompt_tokens { 50 }
    completion_tokens { 25 }
    cost { 0.001 }
    metadata { '{"temperature": 0.7}' }
  end
end