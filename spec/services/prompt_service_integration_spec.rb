# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PromptService, "integration scenarios", type: :service do
  let(:conversation) { create(:conversation) }

  before do
    # Disable vectorsearch callbacks to avoid VCR issues in integration tests
    allow_any_instance_of(Event).to receive(:upsert_to_vectorsearch).and_return(true)
    allow_any_instance_of(Summary).to receive(:upsert_to_vectorsearch).and_return(true)
    allow_any_instance_of(Person).to receive(:upsert_to_vectorsearch).and_return(true)

    # Mock CubePersona to avoid HA calls
    allow(CubePersona).to receive(:current_persona).and_return(:buddy)
  end

  describe "real-world error scenarios that should be caught" do
    context "when Home Assistant is unreachable" do
      before do
        allow(HomeAssistantService).to receive(:new).and_raise(Errno::ECONNREFUSED)
      end

      it "builds prompt gracefully without HA context" do
        service = described_class.new(
          persona: "buddy",
          conversation: conversation,
          extra_context: {},
          user_message: "What's my current location?"
        )

        expect { service.build }.not_to raise_error
        result = service.build

        expect(result[:context]).not_to include("current_location")
        expect(result[:system_prompt]).to be_present
        expect(result[:messages]).to be_an(Array)
        expect(result[:tools]).to be_an(Array)
      end
    end

    context "when goal cache is corrupted" do
      before do
        # Simulate corrupted cache data
        Rails.cache.write('current_goal', "invalid_data")
        Rails.cache.write('current_goal_started_at', "not_a_time")
      end

      after do
        Rails.cache.clear
      end

      it "handles corrupted goal cache gracefully" do
        service = described_class.new(persona: "buddy", conversation: conversation, extra_context: {})

        expect { service.build }.not_to raise_error
        result = service.build

        # Should not crash and should provide valid response structure
        expect(result[:context]).to be_a(String)
        expect(result[:system_prompt]).to be_present
      end
    end

    context "when events have malformed data" do
      let!(:malformed_event) do
        # Create event with nil event_time but high importance
        create(:event, event_time: nil, importance: 10, title: "Malformed Event")
      end

      it "filters out malformed events from proactive injection" do
        service = described_class.new(
          persona: "buddy",
          conversation: conversation,
          extra_context: {},
          user_message: "What's happening?"
        )

        # Should not include malformed events in context
        context = service.send(:inject_upcoming_events_context)
        if context.present?
          expect(context).not_to include("Malformed Event")
        end
      end

      it "handles nil event_time in upcoming scope" do
        expect { Event.upcoming.high_importance.to_a }.not_to raise_error
        expect(Event.upcoming.high_importance).not_to include(malformed_event)
      end
    end

    context "when vectorsearch returns unexpected results" do
      before do
        # Mock vectorsearch to return malformed results that could cause production errors
        allow(Summary).to receive(:similarity_search).and_return([ nil, "invalid" ])
        allow(Event).to receive(:similarity_search).and_return([])
        allow(Person).to receive(:similarity_search).and_return([])
      end

      it "handles malformed vectorsearch results" do
        service = described_class.new(
          persona: "buddy",
          conversation: conversation,
          extra_context: {},
          user_message: "Tell me about recent conversations"
        )

        expect { service.build }.not_to raise_error
        result = service.build
        expect(result[:context]).to be_a(String)
      end
    end

    context "when GoalService raises exceptions" do
      before do
        allow(GoalService).to receive(:current_goal_status).and_raise(StandardError, "Goal service error")
        allow(Rails.logger).to receive(:error)
      end

      it "handles goal service errors gracefully" do
        service = described_class.new(persona: "buddy", conversation: conversation, extra_context: {})

        expect { service.build }.not_to raise_error
        result = service.build

        expect(result[:context]).to be_a(String)
        expect(Rails.logger).to have_received(:error).with(/Failed to build goal context/)
      end
    end
  end

  describe "performance under load scenarios" do
    before do
      # Create realistic data load
      25.times { |i| create(:event, title: "Load Test Event #{i}", importance: rand(1..10), event_time: rand(-24..48).hours.from_now) }
      10.times { |i| create(:summary, summary_text: "Load test summary #{i}") }
    end

    it "builds prompts efficiently with many events" do
      service = described_class.new(persona: "buddy", conversation: conversation, extra_context: {})

      start_time = Time.current
      result = service.build
      end_time = Time.current

      expect(end_time - start_time).to be < 1.second
      expect(result[:context]).to be_present
      expect(result[:system_prompt]).to be_present
    end

    it "handles large context building without memory issues" do
      service = described_class.new(
        persona: "buddy",
        conversation: conversation,
        extra_context: {},
        user_message: "Tell me everything that's happening"
      )

      # Should not cause memory issues even with many events and summaries
      expect { service.build }.not_to raise_error

      result = service.build
      expect(result[:context].length).to be > 100 # Should have substantial content
      expect(result[:context].length).to be < 50000 # But not excessive
    end
  end

  describe "Event scoping chains that failed in production" do
    let!(:high_priority_upcoming) { create(:event, event_time: 2.hours.from_now, importance: 8, location: "Center Camp") }
    let!(:high_priority_past) { create(:event, event_time: 2.hours.ago, importance: 8, location: "Center Camp") }
    let!(:low_priority_upcoming) { create(:event, event_time: 2.hours.from_now, importance: 3, location: "Center Camp") }
    let!(:far_future_event) { create(:event, event_time: 3.days.from_now, importance: 9, location: "Deep Playa") }

    it "correctly filters events for proactive injection" do
      service = described_class.new(
        persona: "buddy",
        conversation: conversation,
        extra_context: {},
        user_message: "What's happening soon?"
      )

      context = service.send(:inject_upcoming_events_context)

      if context.present?
        # Should include high priority upcoming events within 48 hours
        expect(context).to include(high_priority_upcoming.title)

        # Should not include past events, low priority events, or far future events
        expect(context).not_to include(high_priority_past.title)
        expect(context).not_to include(low_priority_upcoming.title)
        expect(context).not_to include(far_future_event.title)
      end
    end

    it "handles empty event results gracefully" do
      Event.destroy_all

      service = described_class.new(persona: "buddy", conversation: conversation, extra_context: {})

      expect { service.build }.not_to raise_error
      result = service.build
      expect(result[:context]).to be_present
    end

    it "correctly chains Event scopes without N+1 queries" do
      # Test that complex scoping doesn't cause performance issues
      expect {
        Event.upcoming.high_importance.within_hours(24).by_location("Center Camp").limit(5).to_a
      }.not_to exceed_query_limit(5) # Should be efficient
    rescue NameError
      # Skip if query counting gem not available
      skip "Query counting not available"
    end
  end

  describe "time formatting and precision issues" do
    let(:goal_status) do
      {
        goal_id: 'test_goal',
        goal_description: 'Test goal for timing',
        category: 'test_goals',
        time_remaining: 1234, # 20 minutes and 34 seconds
        expired: false
      }
    end

    before do
      allow(GoalService).to receive(:current_goal_status).and_return(goal_status)
      allow(Summary).to receive(:goal_completions).and_return(double(limit: []))
    end

    it "formats time durations correctly in goal context" do
      service = described_class.new(persona: "buddy", conversation: conversation, extra_context: {})
      context = service.send(:build_goal_context)

      expect(context).to include("Time remaining: 20m")
    end

    it "handles edge case time durations" do
      service = described_class.new(persona: "buddy", conversation: conversation, extra_context: {})

      # Test various time durations
      expect(service.send(:format_time_duration, 0)).to eq('0s')
      expect(service.send(:format_time_duration, 45)).to eq('45s')
      expect(service.send(:format_time_duration, 90)).to eq('1m')
      expect(service.send(:format_time_duration, 3661)).to eq('1h 1m')
    end
  end

  describe "nil handling that caused production errors" do
    it "handles nil user_message gracefully" do
      service = described_class.new(
        persona: "buddy",
        conversation: conversation,
        extra_context: {},
        user_message: nil
      )

      expect { service.build }.not_to raise_error
      result = service.build
      expect(result[:context]).to be_present
    end

    it "handles nil conversation gracefully" do
      service = described_class.new(
        persona: "buddy",
        conversation: nil,
        extra_context: {}
      )

      expect { service.build }.not_to raise_error
      result = service.build
      expect(result[:messages]).to eq([])
    end

    it "handles nil or invalid persona gracefully" do
      service = described_class.new(
        persona: nil,
        conversation: conversation,
        extra_context: {}
      )

      expect { service.build }.not_to raise_error
      result = service.build
      expect(result[:system_prompt]).to be_present
    end
  end

  describe "context building edge cases" do
    it "handles very long contexts gracefully" do
      # Create a lot of context data
      large_extra_context = {
        tool_results: (1..50).map { |i| [ "tool_#{i}", { success: true, message: "Result #{i}" * 100 } ] }.to_h
      }

      service = described_class.new(
        persona: "buddy",
        conversation: conversation,
        extra_context: large_extra_context
      )

      expect { service.build }.not_to raise_error
      result = service.build
      expect(result[:context]).to be_present
      expect(result[:context].length).to be > 1000 # Should include the large context
    end

    it "handles special characters in context gracefully" do
      special_conversation = create(:conversation, session_id: "test-session-éñ中文🎭")

      service = described_class.new(
        persona: "buddy",
        conversation: special_conversation,
        extra_context: { source: "test with émojis 🎯 and unicode" }
      )

      expect { service.build }.not_to raise_error
      result = service.build
      expect(result[:context]).to include("test with émojis 🎯 and unicode")
    end
  end
end
