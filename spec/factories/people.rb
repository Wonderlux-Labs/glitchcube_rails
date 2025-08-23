# frozen_string_literal: true

FactoryBot.define do
  factory :person do
    sequence(:name) { |n| "Person #{n}" }
    description { "A test person for the specs" }
    relationship { %w[friend colleague acquaintance family stranger].sample }
    last_seen_at { 1.day.ago }
    sequence(:extracted_from_session) { |n| "session_#{n}" }
    metadata { '{}' }
  end
end
