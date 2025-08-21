# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::Query::RagSearch do
  describe ".definition" do
    it "returns proper tool definition" do
      definition = described_class.definition
      
      expect(definition[:type]).to eq("function")
      expect(definition[:function][:name]).to eq("rag_search")
      expect(definition[:function][:parameters][:required]).to eq(["query"])
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
        # Mock the similarity_search methods
        allow(Summary).to receive(:similarity_search).and_return([summary])
        allow(Event).to receive(:similarity_search).and_return([event])
        allow(Person).to receive(:similarity_search).and_return([person])
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
        it "searches only summaries" do
          result = tool.call(query: "fire spinning", type: "summaries")
          
          expect(result[:results][:summaries]).to be_present
          expect(result[:results][:events]).to be_empty
          expect(result[:results][:people]).to be_empty
        end

        it "searches only events" do
          result = tool.call(query: "fire spinning", type: "events")
          
          expect(result[:results][:summaries]).to be_empty
          expect(result[:results][:events]).to be_present
          expect(result[:results][:people]).to be_empty
        end

        it "searches only people" do
          result = tool.call(query: "fire spinning", type: "people")
          
          expect(result[:results][:summaries]).to be_empty
          expect(result[:results][:events]).to be_empty
          expect(result[:results][:people]).to be_present
        end
      end

      context "with limit parameter" do
        it "respects limit parameter" do
          result = tool.call(query: "fire spinning", limit: 2)
          
          expect(Summary).to have_received(:similarity_search).with("fire spinning", limit: 1)
          expect(Event).to have_received(:similarity_search).with("fire spinning", limit: 1)
          expect(Person).to have_received(:similarity_search).with("fire spinning", limit: 1)
        end

        it "clamps limit between 1 and 10" do
          tool.call(query: "test", limit: 0)
          expect(Summary).to have_received(:similarity_search).with("test", limit: 1)
          
          tool.call(query: "test", limit: 20)
          expect(Summary).to have_received(:similarity_search).with("test", limit: 1)
        end
      end

      context "when no results found" do
        before do
          allow(Summary).to receive(:similarity_search).and_return([])
          allow(Event).to receive(:similarity_search).and_return([])
          allow(Person).to receive(:similarity_search).and_return([])
        end

        it "returns no results message" do
          result = tool.call(query: "nonexistent")
          
          expect(result[:success]).to be true
          expect(result[:message]).to include("No results found")
          expect(result[:total_results]).to eq(0)
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
        summaries = [summary]
        results = tool.send(:search_summaries, "test", 5)
        
        # Mock the similarity_search to return our summary
        allow(Summary).to receive(:similarity_search).and_return(summaries)
        results = tool.send(:search_summaries, "test", 5)
        
        result = results.first
        expect(result[:text]).to eq(summary.summary_text)
        expect(result[:message_count]).to eq(5)
      end
    end

    describe "event formatting" do
      it "indicates upcoming vs past events" do
        allow(Event).to receive(:similarity_search).and_return([upcoming_event, past_event])
        results = tool.send(:search_events, "test", 5)
        
        upcoming_result = results.find { |r| r[:id] == upcoming_event.id }
        past_result = results.find { |r| r[:id] == past_event.id }
        
        expect(upcoming_result[:upcoming]).to be true
        expect(past_result[:upcoming]).to be false
      end
    end

    describe "person formatting" do
      it "formats last seen date" do
        allow(Person).to receive(:similarity_search).and_return([person])
        results = tool.send(:search_people, "test", 5)
        
        result = results.first
        expect(result[:last_seen]).to match(/\d{2}\/\d{2}\/\d{4}/)
        expect(result[:relationship]).to eq("friend")
      end
    end
  end
end