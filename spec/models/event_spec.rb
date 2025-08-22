# frozen_string_literal: true

require "rails_helper"

RSpec.describe Event, type: :model do
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
        event = create(:event, event_time: Time.new(2024, 8, 30, 20, 0, 0))
        expect(event.formatted_time).to eq("08/30 at 08:00 PM")
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
        expected_content = "Temple Burn Sacred fire ceremony at the Temple at Temple on 08/31 at 09:00 PM"
        expect(event.vectorsearch_fields_content).to eq(expected_content)
      end

      it "handles missing location gracefully" do
        event.location = nil
        expected_content = "Temple Burn Sacred fire ceremony at the Temple on 08/31 at 09:00 PM"
        expect(event.vectorsearch_fields_content).to eq(expected_content)
      end

      it "handles missing event_time gracefully" do
        event.event_time = nil
        expected_content = "Temple Burn Sacred fire ceremony at the Temple at Temple on No time set"
        expect(event.vectorsearch_fields_content).to eq(expected_content)
      end
    end
  end
end
