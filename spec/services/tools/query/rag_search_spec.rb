# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::Query::RagSearch do
  # The tool chains Model.similarity_search(query).limit(n). Wrap an array of
  # records so it responds to #limit (returning the underlying records).
  def limitable(records)
    relation = double("similarity_relation")
    allow(relation).to receive(:limit) { |n| records.first(n) }
    relation
  end

  before do
    # Creating Summary/Event/Person records triggers an after_save
    # :upsert_to_vectorsearch callback that hits the OpenAI embeddings API.
    # Stub it out so model creation doesn't make real HTTP calls (this spec
    # mocks similarity_search directly to drive the tool behavior).
    allow_any_instance_of(Summary).to receive(:upsert_to_vectorsearch)
    allow_any_instance_of(Event).to receive(:upsert_to_vectorsearch)
    allow_any_instance_of(Person).to receive(:upsert_to_vectorsearch)
  end

  describe ".definition" do
    it "returns a proper OpenRouter::Tool definition" do
      definition = described_class.definition

      # Must be an OpenRouter::Tool (homogeneous with sibling tools) so the
      # registry tool list works with LlmService.call_with_tools.
      expect(definition).to be_a(OpenRouter::Tool)
      expect(definition.name).to eq("rag_search")
    end
  end

  describe ".description" do
    it "returns human-readable description" do
      expect(described_class.description).to be_a(String)
      expect(described_class.description).to include("semantic search")
    end
  end

  describe ".tool_type" do
    it "returns sync" do
      expect(described_class.tool_type).to eq(:sync)
    end
  end

  describe "#call" do
    let(:tool) { described_class.new }

    context "with empty query" do
      it "returns error response" do
        result = tool.call(query: "")

        expect(result[:success]).to be false
        expect(result[:error]).to include("empty")
      end
    end

    context "with valid query" do
      let!(:summary) { create(:summary, summary_text: "Discussion about fire spinning") }
      let!(:event) { create(:event, title: "Fire Show", description: "Amazing fire spinning performance") }
      let!(:person) { create(:person, name: "Alice", description: "Expert fire spinner") }

      before do
        # The tool now calls Model.similarity_search(query).limit(n), so the
        # mocked return must respond to #limit (returns the records array).
        allow(Summary).to receive(:similarity_search).and_return(limitable([ summary ]))
        allow(Event).to receive(:similarity_search).and_return(limitable([ event ]))
        allow(Person).to receive(:similarity_search).and_return(limitable([ person ]))
      end

      context "searching all types" do
        it "searches summaries, events, and people" do
          result = tool.call(query: "fire spinning")

          expect(result[:success]).to be true
          expect(result[:results][:summaries]).to be_present
          expect(result[:results][:events]).to be_present
          expect(result[:results][:people]).to be_present
        end

        it "formats results correctly" do
          result = tool.call(query: "fire spinning")

          summary_result = result[:results][:summaries].first
          expect(summary_result[:type]).to eq("summary")
          expect(summary_result[:text]).to eq(summary.summary_text)

          event_result = result[:results][:events].first
          expect(event_result[:type]).to eq("event")
          expect(event_result[:title]).to eq(event.title)

          person_result = result[:results][:people].first
          expect(person_result[:type]).to eq("person")
          expect(person_result[:name]).to eq(person.name)
        end
      end

      context "searching specific type" do
        # When a specific type is requested the tool only populates that key;
        # the other result keys are left unset (nil), not empty arrays.
        it "searches only summaries" do
          result = tool.call(query: "fire spinning", type: "summaries")

          expect(result[:results][:summaries]).to be_present
          expect(result[:results][:events]).to be_nil
          expect(result[:results][:people]).to be_nil
        end

        it "searches only events" do
          result = tool.call(query: "fire spinning", type: "events")

          expect(result[:results][:summaries]).to be_nil
          expect(result[:results][:events]).to be_present
          expect(result[:results][:people]).to be_nil
        end

        it "searches only people" do
          result = tool.call(query: "fire spinning", type: "people")

          expect(result[:results][:summaries]).to be_nil
          expect(result[:results][:events]).to be_nil
          expect(result[:results][:people]).to be_present
        end
      end

      context "with limit parameter" do
        it "respects limit parameter" do
          result = tool.call(query: "fire spinning", limit: 2)

          # "all" splits the limit across 3 types: max(2/3, 1) == 1 per type,
          # applied via .limit(1) on the relation.
          expect(Summary).to have_received(:similarity_search).with("fire spinning")
          expect(Event).to have_received(:similarity_search).with("fire spinning")
          expect(Person).to have_received(:similarity_search).with("fire spinning")
        end

        it "clamps limit between 1 and 10" do
          # limit is clamped to 1..10 and applied via .limit on the relation;
          # the query argument is unchanged, so both calls look identical.
          tool.call(query: "test", limit: 0)
          tool.call(query: "test", limit: 20)
          expect(Summary).to have_received(:similarity_search).with("test").twice
        end
      end

      context "when no results found" do
        before do
          allow(Summary).to receive(:similarity_search).and_return(limitable([]))
          allow(Event).to receive(:similarity_search).and_return(limitable([]))
          allow(Person).to receive(:similarity_search).and_return(limitable([]))
        end

        it "returns no results message" do
          result = tool.call(query: "nonexistent")

          expect(result[:success]).to be true
          expect(result[:message]).to include("No results found")
          # The no-results branch does not set :total_results.
          expect(result[:results].values.sum { |v| v&.size.to_i }).to eq(0)
        end
      end

      context "when search fails" do
        before do
          allow(Summary).to receive(:similarity_search).and_raise(StandardError.new("Search error"))
        end

        it "handles errors gracefully" do
          result = tool.call(query: "failing search")

          expect(result[:success]).to be false
          expect(result[:error]).to include("Search failed")
        end
      end
    end
  end

  describe "result formatting" do
    let(:tool) { described_class.new }
    let(:summary) { create(:summary, summary_text: "Long text " * 20, message_count: 5) }
    let(:upcoming_event) { create(:event, event_time: 2.hours.from_now, importance: 8) }
    let(:past_event) { create(:event, event_time: 2.hours.ago, importance: 6) }
    let(:person) { create(:person, name: "Bob", relationship: "friend", last_seen_at: 1.week.ago) }

    describe "summary formatting" do
      it "includes metadata from summary" do
        # Mock the similarity_search to return our summary
        allow(Summary).to receive(:similarity_search).and_return(limitable([ summary ]))
        results = tool.send(:search_summaries, "test", 5)

        result = results.first
        expect(result[:text]).to eq(summary.summary_text)
        expect(result[:message_count]).to eq(5)
      end
    end

    describe "event formatting" do
      it "indicates upcoming vs past events" do
        allow(Event).to receive(:similarity_search).and_return(limitable([ upcoming_event, past_event ]))
        results = tool.send(:search_events, "test", 5)

        upcoming_result = results.find { |r| r[:id] == upcoming_event.id }
        past_result = results.find { |r| r[:id] == past_event.id }

        expect(upcoming_result[:upcoming]).to be true
        expect(past_result[:upcoming]).to be false
      end
    end

    describe "person formatting" do
      it "formats last seen date" do
        allow(Person).to receive(:similarity_search).and_return(limitable([ person ]))
        results = tool.send(:search_people, "test", 5)

        result = results.first
        expect(result[:last_seen]).to match(/\d{2}\/\d{2}\/\d{4}/)
        expect(result[:relationship]).to eq("friend")
      end
    end
  end
end
