FactoryBot.define do
  factory :event do
    title { "Fire Performance at Center Camp" }
    description { "Amazing fire spinning performance with live music" }
    event_time { 2.hours.from_now }
    location { "Center Camp" }
    importance { 6 }
    extracted_from_session { "test-session-#{rand(1000)}" }
    metadata { { source: 'test', context: 'burning_man' }.to_json }
  end
end
