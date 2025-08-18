FactoryBot.define do
  factory :event do
    title { "MyString" }
    description { "MyText" }
    event_time { "2025-08-17 22:44:59" }
    location { "MyString" }
    importance { 1 }
    extracted_from_session { "MyString" }
    metadata { "MyText" }
  end
end
