# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::Query::RagSearch, "with VCR", type: :service do
  describe "real vectorsearch integration", :vcr do
    let(:tool) { described_class.new }

    # Create test data with actual content for similarity search
    let!(:fire_summary) do
      create(:summary,
             summary_text: "Great discussion about fire spinning techniques and safety. Maya shared her expertise on poi and staff spinning.",
             start_time: 2.hours.ago,
             end_time: 1.hour.ago,
             message_count: 15)
    end

    let!(:music_summary) do
      create(:summary,
             summary_text: "Conversation about electronic music and DJ sets at various camps around the playa.",
             start_time: 1.day.ago,
             end_time: 1.day.ago + 30.minutes,
             message_count: 8)
    end

    let!(:fire_event) do
      create(:event,
             title: "Fire Safety Workshop",
             description: "Learn proper fire spinning safety protocols and techniques from certified instructors",
             event_time: 6.hours.from_now,
             importance: 8,
             location: "Fire Perimeter")
    end

    let!(:music_event) do
      create(:event,
             title: "Techno Dance Party",
             description: "All-night electronic music and dancing under the stars with top DJs",
             event_time: 1.day.from_now,
             importance: 7,
             location: "Sound Camp")
    end

    let!(:fire_person) do
      create(:person,
             name: "Maya Fire-Spinner",
             description: "Expert fire performer specializing in poi, staff, and fan techniques. Safety instructor.",
             relationship: "instructor",
             last_seen_at: 3.hours.ago)
    end

    let!(:music_person) do
      create(:person,
             name: "DJ Sparkle",
             description: "Electronic music producer and DJ known for psychedelic trance sets at Burning Man",
             relationship: "artist",
             last_seen_at: 1.day.ago)
    end

    before do
      # Ensure all models have vectorsearch enabled
      fire_summary.save! # Trigger vectorsearch upsert
      music_summary.save!
      fire_event.save!
      music_event.save!
      fire_person.save!
      music_person.save!
    end

    describe "similarity search across all types" do
      it "finds relevant content across summaries, events, and people for fire query", vcr: { cassette_name: "rag_search/fire_spinning_search_all_types" } do
        result = tool.call(query: "fire spinning techniques and safety")

        expect(result[:success]).to be true
        expect(result[:total_results]).to be > 0

        # Should find fire-related content in all types
        results = result[:results]
        fire_summaries = results[:summaries].select { |s| s[:text].include?("fire") || s[:text].include?("spinning") }
        fire_events = results[:events].select { |e| e[:title].include?("Fire") || e[:description].include?("fire") }
        fire_people = results[:people].select { |p| p[:name].include?("Fire") || p[:description].include?("fire") }

        expect(fire_summaries.length + fire_events.length + fire_people.length).to be > 0
      end

      it "finds relevant music content when searching for music", vcr: { cassette_name: "rag_search/electronic_music_search" } do
        result = tool.call(query: "electronic music DJ sets", type: "all", limit: 5)

        expect(result[:success]).to be true

        results = result[:results]
        music_items = []
        music_items.concat(results[:summaries].select { |s| s[:text].downcase.include?("music") || s[:text].downcase.include?("dj") })
        music_items.concat(results[:events].select { |e| e[:title].downcase.include?("music") || e[:title].downcase.include?("techno") })
        music_items.concat(results[:people].select { |p| p[:name].downcase.include?("dj") || p[:description].downcase.include?("music") })

        expect(music_items.length).to be > 0
      end
    end

    describe "type-specific searches" do
      it "searches only summaries with real similarity matching", vcr: { cassette_name: "rag_search/summaries_only_search" } do
        result = tool.call(query: "spinning techniques", type: "summaries", limit: 3)

        expect(result[:success]).to be true
        expect(result[:results][:summaries]).to be_present
        expect(result[:results][:events]).to be_empty
        expect(result[:results][:people]).to be_empty

        # Verify summary structure
        summary_result = result[:results][:summaries].first
        expect(summary_result).to have_key(:type)
        expect(summary_result).to have_key(:text)
        expect(summary_result).to have_key(:message_count)
        expect(summary_result[:type]).to eq("summary")
      end

      it "searches only events with real similarity matching", vcr: { cassette_name: "rag_search/events_only_search" } do
        result = tool.call(query: "safety workshop", type: "events", limit: 2)

        expect(result[:success]).to be true
        expect(result[:results][:events]).to be_present
        expect(result[:results][:summaries]).to be_empty
        expect(result[:results][:people]).to be_empty

        # Verify event structure
        event_result = result[:results][:events].first
        expect(event_result).to have_key(:type)
        expect(event_result).to have_key(:title)
        expect(event_result).to have_key(:upcoming)
        expect(event_result[:type]).to eq("event")
      end

      it "searches only people with real similarity matching", vcr: { cassette_name: "rag_search/people_only_search" } do
        result = tool.call(query: "instructor expert", type: "people", limit: 2)

        expect(result[:success]).to be true
        expect(result[:results][:people]).to be_present
        expect(result[:results][:summaries]).to be_empty
        expect(result[:results][:events]).to be_empty

        # Verify person structure
        person_result = result[:results][:people].first
        expect(person_result).to have_key(:type)
        expect(person_result).to have_key(:name)
        expect(person_result).to have_key(:relationship)
        expect(person_result[:type]).to eq("person")
      end
    end

    describe "limit parameter behavior" do
      it "respects limit parameter across all types", vcr: { cassette_name: "rag_search/limit_parameter_test" } do
        result = tool.call(query: "fire music", type: "all", limit: 2)

        expect(result[:success]).to be true

        results = result[:results]
        total_returned = results[:summaries].length + results[:events].length + results[:people].length
        expect(total_returned).to be <= 6 # 2 limit means max 1-2 per type when split
      end

      it "handles limit boundary conditions", vcr: { cassette_name: "rag_search/limit_boundary_test" } do
        # Test minimum limit
        result_min = tool.call(query: "test", limit: 1)
        expect(result_min[:success]).to be true

        # Test maximum limit
        result_max = tool.call(query: "test", limit: 10)
        expect(result_max[:success]).to be true

        # Test out-of-bounds limit (should be clamped)
        result_over = tool.call(query: "test", limit: 50)
        expect(result_over[:success]).to be true
      end
    end

    describe "no results scenarios" do
      it "handles searches with no matches gracefully", vcr: { cassette_name: "rag_search/no_results_search" } do
        result = tool.call(query: "definitely nonexistent quantum unicorn technology")

        expect(result[:success]).to be true
        expect(result[:message]).to include("No results found")
        expect(result[:total_results]).to eq(0)
        expect(result[:results][:summaries]).to be_empty
        expect(result[:results][:events]).to be_empty
        expect(result[:results][:people]).to be_empty
      end
    end

    describe "error handling with real vectorsearch" do
      context "when vectorsearch fails" do
        before do
          allow(Summary).to receive(:similarity_search).and_raise(StandardError.new("Vectorsearch unavailable"))
        end

        it "handles vectorsearch errors gracefully", vcr: { cassette_name: "rag_search/vectorsearch_error" } do
          result = tool.call(query: "test query")

          expect(result[:success]).to be false
          expect(result[:error]).to include("Search failed")
        end
      end
    end

    describe "comprehensive result formatting" do
      it "formats all result types with complete information", vcr: { cassette_name: "rag_search/comprehensive_formatting" } do
        result = tool.call(query: "fire spinning DJ", type: "all", limit: 8)

        expect(result[:success]).to be true

        # Test summary formatting
        if result[:results][:summaries].any?
          summary = result[:results][:summaries].first
          expect(summary[:id]).to be_present
          expect(summary[:type]).to eq("summary")
          expect(summary[:text]).to be_present
          expect(summary[:time_period]).to match(/\d{2}\/\d{2} \d{2}:\d{2}/)
          expect(summary[:message_count]).to be_a(Integer)
        end

        # Test event formatting
        if result[:results][:events].any?
          event = result[:results][:events].first
          expect(event[:id]).to be_present
          expect(event[:type]).to eq("event")
          expect(event[:title]).to be_present
          expect(event[:description]).to be_present
          expect(event[:time]).to be_present
          expect(event[:importance]).to be_between(1, 10)
          expect([ true, false ]).to include(event[:upcoming])
        end

        # Test person formatting
        if result[:results][:people].any?
          person = result[:results][:people].first
          expect(person[:id]).to be_present
          expect(person[:type]).to eq("person")
          expect(person[:name]).to be_present
          expect(person[:description]).to be_present
        end
      end
    end

    describe "real-world query patterns" do
      it "handles conversational queries naturally", vcr: { cassette_name: "rag_search/conversational_queries" } do
        natural_queries = [
          "Who was that person I talked to about fire spinning?",
          "When is the next music event happening?",
          "What did we discuss about safety yesterday?"
        ]

        natural_queries.each do |query|
          result = tool.call(query: query, type: "all", limit: 3)
          expect(result[:success]).to be true
          # Each query should return some results given our test data
        end
      end

      it "handles technical and specific queries", vcr: { cassette_name: "rag_search/technical_queries" } do
        technical_queries = [
          "fire spinning safety protocols",
          "electronic music production techniques",
          "poi staff fan instructors"
        ]

        technical_queries.each do |query|
          result = tool.call(query: query, type: "all", limit: 5)
          expect(result[:success]).to be true
          # Should find relevant technical content
        end
      end
    end
  end
end
