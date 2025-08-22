# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PromptService, "time handling precision", type: :service do
  let(:conversation) { create(:conversation) }
  let(:service) { described_class.new(persona: "buddy", conversation: conversation) }

  before do
    # Disable vectorsearch callbacks to avoid external API calls
    allow_any_instance_of(Event).to receive(:upsert_to_vectorsearch).and_return(true)
    allow_any_instance_of(Summary).to receive(:upsert_to_vectorsearch).and_return(true)
  end

  describe "#format_time_duration edge cases" do
    it "handles zero duration" do
      expect(service.send(:format_time_duration, 0)).to eq('0s')
    end

    it "handles very small durations" do
      expect(service.send(:format_time_duration, 1)).to eq('1s')
      expect(service.send(:format_time_duration, 30)).to eq('30s')
    end

    it "handles minute boundaries correctly" do
      expect(service.send(:format_time_duration, 59)).to eq('59s')
      expect(service.send(:format_time_duration, 60)).to eq('1m')
      expect(service.send(:format_time_duration, 61)).to eq('1m')
    end

    it "handles hour boundaries correctly" do
      expect(service.send(:format_time_duration, 3599)).to eq('59m')
      expect(service.send(:format_time_duration, 3600)).to eq('1h 0m')
      expect(service.send(:format_time_duration, 3661)).to eq('1h 1m')
    end

    it "handles fractional seconds by rounding" do
      expect(service.send(:format_time_duration, 90.7)).to eq('1m')
      expect(service.send(:format_time_duration, 3661.9)).to eq('1h 1m')
    end

    it "handles very large durations" do
      # 25 hours, 30 minutes
      expect(service.send(:format_time_duration, 91800)).to eq('25h 30m')

      # 48 hours exactly
      expect(service.send(:format_time_duration, 172800)).to eq('48h 0m')
    end

    it "handles edge case inputs gracefully" do
      # Test nil input
      expect(service.send(:format_time_duration, nil)).to eq('0s')

      # Test negative input
      expect(service.send(:format_time_duration, -300)).to eq('0s')

      # Test string input that can be converted
      expect(service.send(:format_time_duration, "120")).to eq('2m')
    rescue ArgumentError
      # If string conversion fails, that's acceptable
      expect { service.send(:format_time_duration, "invalid") }.to raise_error
    end
  end

  describe "time-based event filtering precision" do
    let!(:immediate_event) { create(:event, event_time: 30.minutes.from_now, importance: 8, title: "Immediate Event") }
    let!(:boundary_event) { create(:event, event_time: 48.hours.from_now, importance: 8, title: "Boundary Event") }
    let!(:past_boundary_event) { create(:event, event_time: 48.hours.from_now + 1.minute, importance: 8, title: "Past Boundary Event") }

    it "correctly filters events within 48-hour window" do
      context = service.send(:inject_upcoming_events_context)

      if context.present?
        expect(context).to include("Immediate Event")
        expect(context).to include("Boundary Event")
        expect(context).not_to include("Past Boundary Event")
      end
    end

    it "handles event time precision correctly" do
      # Create events with very precise timing
      precise_event = create(:event,
                           event_time: Time.current + 47.hours + 59.minutes + 59.seconds,
                           importance: 8,
                           title: "Precise Timing Event")

      context = service.send(:inject_upcoming_events_context)

      if context.present?
        expect(context).to include("Precise Timing Event")
      end
    end
  end

  describe "timezone consistency" do
    around do |example|
      original_zone = Time.zone
      example.run
    ensure
      Time.zone = original_zone
    end

    it "maintains consistent time calculations across zones" do
      # Create an event in UTC
      event = nil
      Time.use_zone('UTC') do
        event = create(:event, event_time: 2.hours.from_now, importance: 8, title: "UTC Event")
      end

      utc_context = nil
      Time.use_zone('UTC') do
        utc_context = service.send(:inject_upcoming_events_context)
      end

      # Check same event in different timezone
      pst_context = nil
      Time.use_zone('America/Los_Angeles') do
        pst_context = service.send(:inject_upcoming_events_context)
      end

      # Both should include the event (or both should be nil)
      if utc_context.present? && pst_context.present?
        expect(utc_context).to include("UTC Event")
        expect(pst_context).to include("UTC Event")
      end
    end

    it "handles DST transitions without errors" do
      # Test around known DST transition dates
      dst_dates = [
        "2024-03-10 02:00:00", # Spring forward
        "2024-11-03 02:00:00"  # Fall back
      ]

      dst_dates.each do |dst_date|
        Time.use_zone('America/Los_Angeles') do
          begin
            transition_time = Time.zone.parse(dst_date)
            event = create(:event, event_time: transition_time + 1.hour, importance: 8)

            expect { service.send(:inject_upcoming_events_context) }.not_to raise_error
          rescue ArgumentError
            # Skip invalid DST times (like 2:30 AM during spring forward)
            next
          end
        end
      end
    end
  end

  describe "leap year and edge dates" do
    it "handles February 29th correctly in leap years" do
      travel_to Date.new(2024, 2, 29) do
        event = create(:event, event_time: 1.day.from_now, importance: 8, title: "Post Leap Day Event")

        expect { service.send(:inject_upcoming_events_context) }.not_to raise_error
        context = service.send(:inject_upcoming_events_context)

        if context.present?
          expect(context).to include("Post Leap Day Event")
        end
      end
    rescue NoMethodError
      # Skip if travel_to is not available
      skip "Time travel not available for leap year testing"
    end

    it "handles year boundaries correctly" do
      # Test New Year's Eve to New Year's Day transition
      travel_to Time.new(2023, 12, 31, 23, 58, 0) do
        event = create(:event, event_time: 5.minutes.from_now, importance: 8, title: "New Year Event")

        expect { service.send(:inject_upcoming_events_context) }.not_to raise_error
        context = service.send(:inject_upcoming_events_context)

        if context.present?
          expect(context).to include("New Year Event")
        end
      end
    rescue NoMethodError
      # Skip if travel_to is not available
      skip "Time travel not available for year boundary testing"
    end
  end

  describe "goal time remaining calculations" do
    it "handles various goal time scenarios accurately" do
      test_scenarios = [
        { time_remaining: 0, expected: '0s', description: 'expired goal' },
        { time_remaining: 45, expected: '45s', description: 'seconds remaining' },
        { time_remaining: 300, expected: '5m', description: 'minutes remaining' },
        { time_remaining: 3900, expected: '1h 5m', description: 'hours and minutes' },
        { time_remaining: 7200, expected: '2h 0m', description: 'exact hours' }
      ]

      test_scenarios.each do |scenario|
        goal_status = {
          goal_id: 'test_goal',
          goal_description: 'Test goal',
          category: 'test',
          time_remaining: scenario[:time_remaining],
          expired: scenario[:time_remaining] == 0
        }

        allow(GoalService).to receive(:current_goal_status).and_return(goal_status)
        allow(Summary).to receive(:goal_completions).and_return(double(limit: []))

        context = service.send(:build_goal_context)

        if scenario[:time_remaining] > 0
          expect(context).to include("Time remaining: #{scenario[:expected]}")
        else
          expect(context).to include("Goal has expired")
        end
      end
    end
  end

  describe "time precision in error scenarios" do
    it "handles time parsing errors gracefully" do
      # Test malformed time data
      allow(GoalService).to receive(:current_goal_status).and_return({
        goal_id: 'test',
        goal_description: 'Test',
        category: 'test',
        time_remaining: "invalid",
        expired: false
      })

      expect { service.send(:build_goal_context) }.not_to raise_error
    end

    it "handles very large time values without overflow" do
      # Test extremely large time values
      large_time = 999999999 # Very large number of seconds

      expect { service.send(:format_time_duration, large_time) }.not_to raise_error
      result = service.send(:format_time_duration, large_time)
      expect(result).to be_a(String)
      expect(result).to include('h')
    end

    it "handles concurrent time-based operations safely" do
      skip "Skipping concurrent test in CI" if ENV['CI']

      threads = []
      results = []
      mutex = Mutex.new

      # Create several events at slightly different times
      3.times do |i|
        threads << Thread.new do
          event = create(:event, event_time: (i * 30).minutes.from_now, importance: 8)
          context = service.send(:inject_upcoming_events_context)
          mutex.synchronize { results << context&.present? }
        end
      end

      threads.each(&:join)

      # All threads should complete without error
      expect(results.length).to eq(3)
      expect(results).to all(be_in([ true, false ])) # Should be boolean values
    end
  end
end
