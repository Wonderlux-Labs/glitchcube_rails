require 'rails_helper'

RSpec.describe Event, type: :model do
  describe 'validations' do
    it 'requires title, description, event_time, importance, and extracted_from_session' do
      event = Event.new
      expect(event).not_to be_valid
      expect(event.errors.attribute_names).to include(:title, :description, :event_time, :importance, :extracted_from_session)
    end

    it 'validates importance is within range' do
      event = build(:event, importance: 11)
      expect(event).not_to be_valid
      expect(event.errors[:importance]).to include('is not included in the list')
    end
  end

  describe 'scopes' do
    let!(:upcoming_event) { create(:event, event_time: 1.hour.from_now) }
    let!(:past_event) { create(:event, event_time: 1.hour.ago) }
    let!(:high_importance) { create(:event, importance: 9) }
    let!(:low_importance) { create(:event, importance: 3) }

    it 'filters upcoming events' do
      expect(Event.upcoming).to include(upcoming_event)
      expect(Event.upcoming).not_to include(past_event)
    end

    it 'filters past events' do
      expect(Event.past).to include(past_event)
      expect(Event.past).not_to include(upcoming_event)
    end

    it 'filters by importance levels' do
      expect(Event.high_importance).to include(high_importance)
      expect(Event.low_importance).to include(low_importance)
    end
  end

  describe 'instance methods' do
    let(:upcoming_event) { create(:event, event_time: 2.hours.from_now) }
    let(:past_event) { create(:event, event_time: 1.hour.ago) }

    it 'determines if event is upcoming' do
      expect(upcoming_event.upcoming?).to be true
      expect(past_event.upcoming?).to be false
    end

    it 'calculates hours until event' do
      expect(upcoming_event.hours_until_event).to be_within(0.1).of(2.0)
      expect(past_event.hours_until_event).to be_nil
    end
  end
end
