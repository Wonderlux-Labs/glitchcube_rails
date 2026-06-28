# frozen_string_literal: true

FactoryBot.define do
  factory :memory do
    content { "Someone asked if the cube dreams" }
    category { "fact" }
    importance { 5 }

    trait :event do
      category { "event" }
      content { "Fire spinning at the main stage" }
      occurs_at { 1.day.from_now.change(hour: 22) }
    end

    trait :vibe do
      category { "vibe" }
      content { "The crowd tonight is rowdy and affectionate" }
      emotion { "amused" }
    end

    trait :important do
      importance { 9 }
    end
  end
end
