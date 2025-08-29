# spec/services/prompts/context_builder_spec.rb
require 'rails_helper'

RSpec.describe Prompts::ContextBuilder do
  let(:conversation) { create(:conversation) }
  let(:extra_context) { {} }
  let(:user_message) { "Hello there!" }

  # Mock external dependencies
  before do
    allow(HaDataSync).to receive(:entity_state).with("sensor.cube_mode").and_return("active")
    allow(HaDataSync).to receive(:low_power_mode?).and_return(false)
    allow(HaDataSync).to receive(:get_context_attribute).and_return(nil)
    allow(HaDataSync).to receive(:extended_location).and_return("Burning Man")
    allow(GoalService).to receive(:current_goal_status).and_return(nil)
    allow(Time).to receive(:current).and_return(Time.parse("2025-08-23 14:30:00 UTC"))
  end

  describe '.build' do
    it 'delegates to instance method' do
      expect_any_instance_of(described_class).to receive(:build).and_return("test context")

      result = described_class.build(
        conversation: conversation,
        extra_context: extra_context,
        user_message: user_message
      )

      expect(result).to eq("test context")
    end
  end

  describe '#build' do
    subject do
      described_class.new(
        conversation: conversation,
        extra_context: extra_context,
        user_message: user_message
      ).build
    end

    it 'includes basic time context' do
      expect(subject).to include("Time:")
      expect(subject).to include("2:30 PM on Saturday")
    end

    it 'builds session context when conversation exists' do
      expect(subject).to include("Session: #{conversation.session_id}")
      expect(subject).to include("Message count: #{conversation.messages.count}")
      expect(subject).to include("Should end?: Think about wrapping up")
    end

    context 'when conversation is nil' do
      let(:conversation) { nil }

      it 'still includes basic time context' do
        expect(subject).to include("Time:")
      end

      it 'does not include session context' do
        expect(subject).not_to include("Session:")
      end
    end

    context 'cube mode context' do
      it 'includes cube mode when available' do
        expect(HaDataSync).to receive(:entity_state).with("sensor.cube_mode").and_return("performance")
        expect(subject).to include("Cube mode: performance")
      end

      it 'excludes cube mode when unavailable' do
        expect(HaDataSync).to receive(:entity_state).with("sensor.cube_mode").and_return("unavailable")
        expect(subject).not_to include("Cube mode:")
      end

      it 'handles cube mode errors gracefully' do
        expect(HaDataSync).to receive(:entity_state).and_raise(StandardError, "Connection failed")
        expect(Rails.logger).to receive(:warn).with(/Could not fetch sensor.cube_mode/)

        expect { subject }.not_to raise_error
      end
    end

    context 'goal context' do
      let(:goal_status) do
        {
          goal_id: 'make_friends',
          goal_description: 'Have meaningful conversations with visitors',
          category: 'social_goals',
          started_at: 10.minutes.ago,
          time_remaining: 1200, # 20 minutes
          expired: false
        }
      end

      before do
        allow(GoalService).to receive(:current_goal_status).and_return(goal_status)
      end

      it 'includes goal information' do
        expect(subject).to include('Current Goal: Have meaningful conversations with visitors')
        expect(subject).to include('Time remaining: 20m')
      end

      context 'when goal is expired' do
        before do
          goal_status[:expired] = true
          goal_status[:time_remaining] = 0
        end

        it 'shows expiration warning' do
          expect(subject).to include('⏰ Goal has expired - consider completing or switching goals')
        end
      end

      context 'when in safety mode' do
        before do
          allow(HaDataSync).to receive(:low_power_mode?).and_return(true)
        end

        it 'shows safety mode message instead of regular goal' do
          expect(subject).to include('YOU ARE IN SAFETY MODE!')
          expect(subject).to include('YOUR BATTERY PERCENTAGE IS DROPPING')
        end
      end
    end

    context 'source context' do
      let(:extra_context) { { source: 'web_interface' } }

      it 'includes source information' do
        expect(subject).to include('Source: web_interface')
      end
    end

    context 'tool results context' do
      let(:extra_context) do
        {
          tool_results: {
            'lights.turn_on' => { success: true, message: 'Lights turned on successfully' },
            'sound.play' => { success: false, error: 'Audio file not found' }
          }
        }
      end

      it 'includes tool results' do
        expect(subject).to include('Recent tool results:')
        expect(subject).to include('lights.turn_on: ✅ SUCCESS - Lights turned on successfully')
        expect(subject).to include('sound.play: ❌ FAILED - Audio file not found')
      end
    end

    context 'enhanced context injection' do
      before do
        allow(HaDataSync).to receive(:get_context_attribute).with("time_of_day").and_return("afternoon")
        allow(HaDataSync).to receive(:get_context_attribute).with("day_of_week").and_return("Friday")
        allow(HaDataSync).to receive(:get_context_attribute).with("current_location").and_return("Center Camp")
      end

      it 'includes time context from Home Assistant' do
        expect(subject).to include('Current time context: It is afternoon on Friday at Center Camp')
      end

      context 'when Event model is defined' do
        before do
          # Mock Event model with empty results but proper chain
          event_relation = double("EventRelation")
          allow(event_relation).to receive(:limit).and_return([])
          allow(event_relation).to receive(:any?).and_return(false)

          allow(Event).to receive(:where).and_return(event_relation)
        end

        it 'attempts to include upcoming events' do
          # Both calls should happen - one for high-priority, one for nearby
          # The nearby call happens because HaDataSync.extended_location returns "Burning Man"
          expect(Event).to receive(:where).twice.and_call_original
          subject
        end
      end
    end

    describe 'time duration formatting' do
      let(:builder) { described_class.new(conversation: conversation, extra_context: {}, user_message: nil) }

      it 'formats seconds correctly' do
        expect(builder.send(:format_time_duration, 45)).to eq('45s')
      end

      it 'formats minutes correctly' do
        expect(builder.send(:format_time_duration, 90)).to eq('1m')
        expect(builder.send(:format_time_duration, 300)).to eq('5m')
      end

      it 'formats hours and minutes correctly' do
        expect(builder.send(:format_time_duration, 3661)).to eq('1h 1m')
        expect(builder.send(:format_time_duration, 7200)).to eq('2h 0m')
      end
    end
  end
end
