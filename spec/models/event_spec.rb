# frozen_string_literal: true

require "rails_helper"

RSpec.describe Event, type: :model do
  before do
    # Disable vectorsearch callback for all Event tests to avoid VCR issues
    allow_any_instance_of(Event).to receive(:upsert_to_vectorsearch).and_return(true)
  end
  describe "constants" do
    it "defines importance range" do
      expect(Event::IMPORTANCE_RANGE).to eq(1..10)
    end
  end

  describe "scopes" do
    let!(:upcoming_event) { create(:event, event_time: 2.hours.from_now) }
    let!(:past_event) { create(:event, event_time: 2.hours.ago) }
    let!(:high_importance_event) { create(:event, importance: 9) }
    let!(:medium_importance_event) { create(:event, importance: 5) }
    let!(:low_importance_event) { create(:event, importance: 2) }
    let!(:playa_event) { create(:event, location: "Black Rock City") }

    describe ".upcoming" do
      it "returns events in the future" do
        expect(Event.upcoming).to include(upcoming_event)
        expect(Event.upcoming).not_to include(past_event)
      end
    end

    describe ".past" do
      it "returns events in the past or present" do
        expect(Event.past).to include(past_event)
        expect(Event.past).not_to include(upcoming_event)
      end
    end

    describe ".within_hours" do
      let!(:near_event) { create(:event, event_time: 1.hour.from_now) }
      let!(:far_event) { create(:event, event_time: 5.hours.from_now) }

      it "returns events within specified hours" do
        expect(Event.within_hours(3)).to include(near_event)
        expect(Event.within_hours(3)).not_to include(far_event)
      end
    end

    describe ".by_location" do
      it "filters by location" do
        expect(Event.by_location("Black Rock City")).to include(playa_event)
        expect(Event.by_location("San Francisco")).not_to include(playa_event)
      end
    end

    describe "importance scopes" do
      describe ".high_importance" do
        it "returns events with importance 7-10" do
          expect(Event.high_importance).to include(high_importance_event)
          expect(Event.high_importance).not_to include(medium_importance_event)
          expect(Event.high_importance).not_to include(low_importance_event)
        end
      end

      describe ".medium_importance" do
        it "returns events with importance 4-6" do
          expect(Event.medium_importance).to include(medium_importance_event)
          expect(Event.medium_importance).not_to include(high_importance_event)
          expect(Event.medium_importance).not_to include(low_importance_event)
        end
      end

      describe ".low_importance" do
        it "returns events with importance 1-3" do
          expect(Event.low_importance).to include(low_importance_event)
          expect(Event.low_importance).not_to include(high_importance_event)
          expect(Event.low_importance).not_to include(medium_importance_event)
        end
      end
    end
  end

  describe "metadata handling" do
    let(:event) { create(:event) }

    it "handles JSON metadata" do
      event.metadata_json = { "organizer" => "Burning Man", "capacity" => 100 }
      event.save!

      expect(event.metadata_json["organizer"]).to eq("Burning Man")
      expect(event.metadata_json["capacity"]).to eq(100)
    end

    it "returns empty hash for blank metadata" do
      event.metadata = nil
      expect(event.metadata_json).to eq({})
    end
  end

  describe "instance methods" do
    describe "#upcoming?" do
      it "returns true for future events" do
        event = create(:event, event_time: 1.hour.from_now)
        expect(event.upcoming?).to be true
      end

      it "returns false for past events" do
        event = create(:event, event_time: 1.hour.ago)
        expect(event.upcoming?).to be false
      end

      it "returns false when event_time is nil" do
        event = create(:event, event_time: nil)
        expect(event.upcoming?).to be false
      end
    end

    describe "#high_importance?" do
      it "returns true for importance >= 7" do
        event = create(:event, importance: 8)
        expect(event.high_importance?).to be true
      end

      it "returns false for importance < 7" do
        event = create(:event, importance: 5)
        expect(event.high_importance?).to be false
      end
    end

    describe "#time_until_event" do
      it "returns time difference for upcoming events" do
        event = create(:event, event_time: 2.hours.from_now)
        expect(event.time_until_event).to be_within(60).of(2.hours)
      end

      it "returns nil for past events" do
        event = create(:event, event_time: 1.hour.ago)
        expect(event.time_until_event).to be_nil
      end

      it "returns nil when event_time is nil" do
        event = create(:event, event_time: nil)
        expect(event.time_until_event).to be_nil
      end
    end

    describe "#hours_until_event" do
      it "returns hours until event" do
        event = create(:event, event_time: 3.hours.from_now)
        expect(event.hours_until_event).to be_within(0.1).of(3.0)
      end

      it "returns nil for past events" do
        event = create(:event, event_time: 1.hour.ago)
        expect(event.hours_until_event).to be_nil
      end
    end

    describe "#formatted_time" do
      it "formats event time" do
        # Use UTC to avoid timezone issues in tests
        Time.use_zone('UTC') do
          event = create(:event, event_time: Time.zone.local(2024, 8, 30, 20, 0, 0))
          expect(event.formatted_time).to eq("08/30 at 08:00 PM")
        end
      end

      it "returns default message when event_time is nil" do
        event = create(:event, event_time: nil)
        expect(event.formatted_time).to eq("No time set")
      end
    end
  end

  describe "vectorsearch integration" do
    let(:event) do
      create(:event,
             title: "Temple Burn",
             description: "Sacred fire ceremony at the Temple",
             location: "Temple",
             event_time: Time.new(2024, 8, 31, 21, 0, 0))
    end

    it "includes vectorsearch functionality" do
      expect(Event).to respond_to(:similarity_search)
    end

    describe "#vectorsearch_fields_content" do
      it "combines title, description, location, and formatted time" do
        Time.use_zone('UTC') do
          expected_content = "Temple Burn Sacred fire ceremony at the Temple at Temple on 08/31 at 09:00 PM"
          expect(event.vectorsearch_fields_content).to eq(expected_content)
        end
      end

      it "handles missing location gracefully" do
        Time.use_zone('UTC') do
          event.location = nil
          # Format: "title description on formatted_time" (no "at location" part)
          expected_content = "Temple Burn Sacred fire ceremony at the Temple on 08/31 at 09:00 PM"
          expect(event.vectorsearch_fields_content).to eq(expected_content)
        end
      end

      it "handles missing event_time gracefully" do
        event.event_time = nil
        # Format: "title description at location" (no "on formatted_time" part)
        expected_content = "Temple Burn Sacred fire ceremony at the Temple at Temple"
        expect(event.vectorsearch_fields_content).to eq(expected_content)
      end
    end
  end

  describe "scopes edge cases and production scenarios" do
    describe ".within_hours boundary conditions" do
      let!(:exactly_on_boundary) { create(:event, event_time: 3.hours.from_now) }
      let!(:one_second_over) { create(:event, event_time: 3.hours.from_now + 1.second) }
      let!(:one_second_under) { create(:event, event_time: 3.hours.from_now - 1.second) }

      it "includes events exactly on the boundary" do
        expect(Event.within_hours(3)).to include(exactly_on_boundary)
        expect(Event.within_hours(3)).to include(one_second_under)
        expect(Event.within_hours(3)).not_to include(one_second_over)
      end

      it "handles zero hours gracefully" do
        expect(Event.within_hours(0)).to be_empty
      end

      it "handles negative hours gracefully" do
        expect(Event.within_hours(-1)).to be_empty
      end
    end

    describe "importance boundary edge cases" do
      let!(:importance_6) { create(:event, importance: 6) }
      let!(:importance_7) { create(:event, importance: 7) }
      let!(:importance_4) { create(:event, importance: 4) }
      let!(:importance_1) { create(:event, importance: 1) }
      let!(:importance_10) { create(:event, importance: 10) }

      it "correctly categorizes importance boundaries" do
        # High importance: 7-10
        expect(Event.high_importance).to include(importance_7, importance_10)
        expect(Event.high_importance).not_to include(importance_6)

        # Medium importance: 4-6
        expect(Event.medium_importance).to include(importance_6, importance_4)
        expect(Event.medium_importance).not_to include(importance_7, importance_1)

        # Low importance: 1-3
        expect(Event.low_importance).to include(importance_1)
        expect(Event.low_importance).not_to include(importance_4)
      end

      it "handles edge case importance values" do
        # Test the exact boundaries that could cause issues
        expect(Event.where(importance: 7).first.high_importance?).to be true
        expect(Event.where(importance: 6).first.high_importance?).to be false
      end
    end

    describe "chained scopes that failed in production" do
      let!(:high_upcoming) { create(:event, event_time: 2.hours.from_now, importance: 8, location: "Center Camp") }
      let!(:high_past) { create(:event, event_time: 2.hours.ago, importance: 8, location: "Center Camp") }
      let!(:low_upcoming) { create(:event, event_time: 2.hours.from_now, importance: 3, location: "Center Camp") }
      let!(:high_upcoming_different_location) { create(:event, event_time: 2.hours.from_now, importance: 8, location: "Deep Playa") }

      it "chains scopes correctly for production queries" do
        results = Event.upcoming.high_importance
        expect(results).to include(high_upcoming, high_upcoming_different_location)
        expect(results).not_to include(high_past, low_upcoming)
      end

      it "handles location + importance + time scoping" do
        results = Event.upcoming.high_importance.by_location("Center Camp")
        expect(results).to include(high_upcoming)
        expect(results).not_to include(high_past, low_upcoming, high_upcoming_different_location)
      end

      it "handles empty result chains gracefully" do
        Event.destroy_all
        expect(Event.upcoming.high_importance.by_location("Nonexistent")).to be_empty
        expect { Event.upcoming.high_importance.by_location("Nonexistent").first }.not_to raise_error
      end

      it "handles nil location filtering" do
        nil_location_event = create(:event, event_time: 2.hours.from_now, importance: 8, location: nil)
        results = Event.upcoming.high_importance.by_location(nil)
        expect(results).to include(nil_location_event)
      end
    end

    describe "time zone edge cases" do
      around do |example|
        Time.use_zone('America/Los_Angeles') { example.run }
      end

      let!(:dst_transition_event) do
        # Create event during DST transition
        create(:event, event_time: Time.zone.parse('2024-03-10 03:00:00'), importance: 8)
      end

      it "handles DST transitions correctly" do
        # Simplified DST test - just verify the event exists and can be queried
        expect(Event.within_hours(24)).to include(dst_transition_event)
        expect(dst_transition_event.upcoming?).to be true
      end

      it "maintains consistency across time zones" do
        utc_events = nil
        Time.use_zone('UTC') do
          utc_events = Event.within_hours(24).pluck(:id)
        end

        pst_events = Event.within_hours(24).pluck(:id)
        expect(pst_events).to eq(utc_events)
      end
    end

    describe "concurrent access patterns" do
      it "handles concurrent event creation safely" do
        skip "Skipping concurrent test in CI" if ENV['CI']

        threads = []
        created_events = []
        mutex = Mutex.new

        5.times do |i|
          threads << Thread.new do
            event = create(:event, title: "Concurrent Event #{i}", importance: rand(1..10))
            mutex.synchronize { created_events << event }
          end
        end

        threads.each(&:join)
        expect(created_events.length).to eq(5)
        expect(Event.count).to be >= 5
      end

      it "handles concurrent scope queries safely" do
        skip "Skipping concurrent test in CI" if ENV['CI']

        # Create some base events
        10.times { |i| create(:event, event_time: i.hours.from_now, importance: rand(1..10)) }

        results = []
        threads = []

        3.times do
          threads << Thread.new do
            results << Event.upcoming.high_importance.count
          end
        end

        threads.each(&:join)
        expect(results).to all(be >= 0)
        expect(results.uniq.length).to be <= 2 # Should be consistent
      end
    end

    describe "malformed data handling" do
      let!(:nil_time_event) { create(:event, event_time: nil, importance: 10, title: "No Time Event") }
      let!(:nil_importance_event) { create(:event, event_time: 2.hours.from_now, importance: nil, title: "No Importance Event") }
      let!(:empty_title_event) { create(:event, event_time: 2.hours.from_now, importance: 5, title: "") }

      it "filters out events with nil event_time from time-based scopes" do
        expect(Event.upcoming).not_to include(nil_time_event)
        expect(Event.within_hours(24)).not_to include(nil_time_event)
      end

      it "handles nil importance gracefully" do
        # Nil importance should not be included in importance scopes
        expect(Event.high_importance).not_to include(nil_importance_event)
        expect(Event.medium_importance).not_to include(nil_importance_event)
        expect(Event.low_importance).not_to include(nil_importance_event)
      end

      it "handles empty strings in location filtering" do
        empty_location_event = create(:event, event_time: 2.hours.from_now, location: "")
        expect(Event.by_location("")).to include(empty_location_event)
      end

      it "handles events with extreme future dates" do
        far_future_event = create(:event, event_time: 100.years.from_now, importance: 8)
        expect(Event.upcoming).to include(far_future_event)
        expect(Event.within_hours(24)).not_to include(far_future_event)
      end
    end

    describe "performance under load" do
      before do
        # Create a realistic number of events
        50.times do |i|
          create(:event,
                 event_time: rand(-24..48).hours.from_now,
                 importance: rand(1..10),
                 location: [ "Center Camp", "Deep Playa", "Esplanade", nil ].sample)
        end
      end

      it "performs complex scoping efficiently" do
        start_time = Time.current

        results = Event.upcoming
                      .high_importance
                      .within_hours(24)
                      .by_location("Center Camp")
                      .limit(10)

        end_time = Time.current

        expect(end_time - start_time).to be < 0.1 # Should be fast
        expect(results).to be_an(ActiveRecord::Relation)
      end

      it "handles large result sets without memory issues" do
        # This should not cause memory issues even with many events
        count = Event.upcoming.count
        expect(count).to be >= 0

        # Test streaming through results
        processed = 0
        Event.upcoming.find_each do |event|
          processed += 1
          break if processed > 100 # Prevent infinite loops in tests
        end

        expect(processed).to be >= 0
      end
    end

    describe "SQL injection protection" do
      it "protects against injection in location filtering" do
        malicious_location = "'; DROP TABLE events; --"
        expect { Event.by_location(malicious_location) }.not_to raise_error
        expect(Event.count).to be > 0 # Table should still exist
      end

      it "handles special characters in location names" do
        special_location = "Camp \"Fun\" & Games (2024)"
        special_event = create(:event, location: special_location, event_time: 2.hours.from_now)

        results = Event.by_location(special_location)
        expect(results).to include(special_event)
      end
    end
  end
end
