# frozen_string_literal: true

FactoryBot.define do
  factory :summary do
    summary_text { 'This is a summary of conversations about technical topics' }
    summary_type { 'session' }
    message_count { 10 }
    start_time { 1.hour.ago }
    end_time { 30.minutes.ago }
    metadata { '{"conversations": 2}' }
  end
end