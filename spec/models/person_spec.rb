# frozen_string_literal: true

require "rails_helper"

RSpec.describe Person, type: :model do
  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:description) }
    it { should validate_presence_of(:extracted_from_session) }
  end

  describe "scopes" do
    let!(:recent_person) { create(:person, last_seen_at: 1.hour.ago) }
    let!(:old_person) { create(:person, last_seen_at: 2.weeks.ago) }
    let!(:friend) { create(:person, relationship: "friend") }
    let!(:colleague) { create(:person, relationship: "colleague") }

    describe ".recent" do
      it "orders by last_seen_at descending" do
        expect(Person.recent.first).to eq(recent_person)
      end
    end

    describe ".by_relationship" do
      it "filters by relationship" do
        expect(Person.by_relationship("friend")).to include(friend)
        expect(Person.by_relationship("friend")).not_to include(colleague)
      end
    end

    describe ".seen_recently" do
      it "returns people seen within the last week" do
        expect(Person.seen_recently).to include(recent_person)
        expect(Person.seen_recently).not_to include(old_person)
      end
    end
  end

  describe "metadata handling" do
    let(:person) { create(:person) }

    it "handles JSON metadata" do
      person.metadata_json = { "source" => "conversation", "confidence" => 0.9 }
      person.save!
      
      expect(person.metadata_json["source"]).to eq("conversation")
      expect(person.metadata_json["confidence"]).to eq(0.9)
    end

    it "returns empty hash for blank metadata" do
      person.metadata = nil
      expect(person.metadata_json).to eq({})
    end
  end

  describe ".find_or_update_person" do
    context "when person exists" do
      let!(:existing_person) do
        create(:person, 
               name: "Alice", 
               description: "Original description",
               relationship: "friend")
      end

      it "updates existing person with new information" do
        result = Person.find_or_update_person(
          name: "Alice",
          description: "New description",
          session_id: "session_123",
          relationship: "best friend",
          additional_metadata: { "updated" => true }
        )

        expect(result).to eq(existing_person)
        expect(result.description).to include("Original description")
        expect(result.description).to include("New description")
        expect(result.relationship).to eq("best friend")
        expect(result.metadata_json["updated"]).to be true
      end

      it "updates last_seen_at" do
        freeze_time do
          result = Person.find_or_update_person(
            name: "Alice",
            description: "Updated",
            session_id: "session_123"
          )
          
          expect(result.last_seen_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    context "when person doesn't exist" do
      it "creates new person" do
        expect {
          Person.find_or_update_person(
            name: "Bob",
            description: "New person",
            session_id: "session_456",
            relationship: "stranger",
            additional_metadata: { "new" => true }
          )
        }.to change(Person, :count).by(1)

        person = Person.find_by(name: "Bob")
        expect(person.description).to eq("New person")
        expect(person.relationship).to eq("stranger")
        expect(person.metadata_json["new"]).to be true
      end
    end
  end

  describe "#update_last_seen!" do
    let(:person) { create(:person, last_seen_at: 1.week.ago) }

    it "updates last_seen_at to current time" do
      freeze_time do
        person.update_last_seen!("new_session")
        expect(person.last_seen_at).to be_within(1.second).of(Time.current)
      end
    end

    it "updates extracted_from_session if provided" do
      person.update_last_seen!("new_session")
      expect(person.extracted_from_session).to eq("new_session")
    end
  end

  describe "associations" do
    let(:person) { create(:person, extracted_from_session: "session_123") }
    let!(:related_summary) { create(:summary, metadata: { conversation_ids: ["session_123"] }.to_json) }
    let!(:related_event) { create(:event, extracted_from_session: "session_123") }

    describe "#related_summaries" do
      it "finds summaries with matching conversation_ids" do
        expect(person.related_summaries).to include(related_summary)
      end
    end

    describe "#related_events" do
      it "finds events with matching extracted_from_session" do
        expect(person.related_events).to include(related_event)
      end
    end
  end

  describe "vectorsearch integration" do
    let(:person) { create(:person, name: "Alice", description: "Loves fire spinning and art") }

    it "includes vectorsearch functionality" do
      expect(Person).to respond_to(:similarity_search)
    end

    describe "#vectorsearch_fields_content" do
      it "combines name and description" do
        expected_content = "#{person.name}: #{person.description}"
        expect(person.vectorsearch_fields_content).to eq(expected_content)
      end
    end
  end
end