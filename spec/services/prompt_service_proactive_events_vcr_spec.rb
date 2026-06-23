# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptService, "proactive events with VCR", type: :service do
  # NOTE: Proactive-event / location context injection was refactored out of
  # PromptService into Prompts::ContextBuilder. The old private methods
  # `inject_upcoming_events_context` and `get_current_location` now live there
  # (the former renamed to `build_upcoming_events_context`). These methods only
  # touch the DB and the (mocked) Home Assistant service — no LLM/OpenRouter call
  # — so the original VCR cassettes were unnecessary and have been removed.
  describe "proactive event injection with real API context" do
    let(:conversation) { create(:conversation, session_id: "proactive_test_session") }
    let(:prompt_service) do
      described_class.new(
        persona: "buddy",
        conversation: conversation,
        extra_context: { source: "vcr_proactive_test" },
        user_message: "What's happening today?"
      )
    end
    # Context-building methods now live on Prompts::ContextBuilder.
    let(:context_builder) do
      Prompts::ContextBuilder.new(
        conversation: conversation,
        extra_context: { source: "vcr_proactive_test" },
        user_message: "What's happening today?"
      )
    end

    before do
      # Avoid OpenAI embedding HTTP calls triggered by Event/Summary creation.
      allow_any_instance_of(Event).to receive(:upsert_to_vectorsearch).and_return(true)
      allow_any_instance_of(Summary).to receive(:upsert_to_vectorsearch).and_return(true)
    end

    describe "high-priority event injection" do
      let!(:critical_event) do
        create(:event,
               title: "Emergency Weather Alert",
               description: "Severe dust storm approaching - seek shelter immediately",
               event_time: 2.hours.from_now,
               importance: 10,
               location: "Playa-wide")
      end

      let!(:important_event) do
        create(:event,
               title: "Temple Burn Ceremony",
               description: "Sacred burning of the Temple structure",
               event_time: 8.hours.from_now,
               importance: 9,
               location: "Temple")
      end

      let!(:regular_event) do
        create(:event,
               title: "Art Walk",
               description: "Casual exploration of art installations",
               event_time: 4.hours.from_now,
               importance: 5, # Not high priority
               location: "Deep Playa")
      end

      it "injects high-priority events automatically in context" do
        # No current location -> only the high-priority block runs.
        # (ContextBuilder reads location via HaDataSync, not HomeAssistantService.new.)
        allow(HaDataSync).to receive(:extended_location).and_return(nil)

        context = context_builder.send(:build_upcoming_events_context)

        expect(context).to include("UPCOMING HIGH-PRIORITY EVENTS")
        expect(context).to include("Emergency Weather Alert")
        expect(context).to include("Temple Burn Ceremony")
        expect(context).not_to include("Art Walk") # Only importance >= 7
        # NOTE: relative-time strings ("2 hours"/"8 hours") were dropped in the
        # refactor; ContextBuilder now formats events with an absolute timestamp.
      end

      it "formats high-priority events with proper urgency indicators" do
        allow(HaDataSync).to receive(:extended_location).and_return(nil)

        context = context_builder.send(:build_upcoming_events_context)

        expect(context).to include("next 48h")
        expect(context).to include("Severe dust storm approaching")
        expect(context).to include("Sacred burning")
      end
    end

    describe "location-based event injection with real HA integration" do
      let!(:nearby_event) do
        create(:event,
               title: "Camp Sunrise Pancake Breakfast",
               description: "Free pancakes and coffee for everyone",
               event_time: 6.hours.from_now,
               importance: 6,
               location: "Center Camp")
      end

      let!(:distant_event) do
        create(:event,
               title: "Deep Playa Sound Bath",
               description: "Meditative sound experience in the deep desert",
               event_time: 4.hours.from_now,
               importance: 6,
               location: "Deep Playa")
      end

      context "when location is available from HA sensor" do
        before do
          # ContextBuilder resolves the current location via HaDataSync, not via
          # HomeAssistantService.new, so stub at that boundary.
          allow(HaDataSync).to receive(:extended_location).and_return("Center Camp")
        end

        it "injects nearby events based on current location" do
          context = context_builder.send(:build_upcoming_events_context)

          expect(context).to include("UPCOMING NEARBY EVENTS")
          expect(context).to include("Camp Sunrise Pancake Breakfast")
          expect(context).not_to include("Deep Playa Sound Bath")

          expect(context).to include("next 24h")
        end

        it "combines high-priority and nearby events correctly" do
          # Add a high-priority event too
          create(:event,
                 title: "Critical Safety Briefing",
                 importance: 8,
                 event_time: 3.hours.from_now)

          context = context_builder.send(:build_upcoming_events_context)

          expect(context).to include("UPCOMING HIGH-PRIORITY EVENTS")
          expect(context).to include("UPCOMING NEARBY EVENTS")
          expect(context).to include("Critical Safety Briefing")
          expect(context).to include("Camp Sunrise Pancake Breakfast")
        end
      end

      context "when location is not available" do
        before do
          allow(HaDataSync).to receive(:extended_location).and_return(nil)
        end

        it "only includes high-priority events without location filtering" do
          context = context_builder.send(:build_upcoming_events_context)

          # No high-priority and no location -> no context at all.
          expect(context.to_s).not_to include("UPCOMING NEARBY EVENTS")
          # Should not include medium-importance events when no location available
          expect(context.to_s).not_to include("Camp Sunrise Pancake Breakfast")
        end
      end

      context "when HA service fails" do
        before do
          allow(HaDataSync).to receive(:extended_location).and_raise(StandardError.new("HA connection failed"))
        end

        it "continues gracefully without location-based events" do
          expect { context_builder.send(:build_upcoming_events_context) }.not_to raise_error

          context = context_builder.send(:build_upcoming_events_context)
          expect(context.to_s).not_to include("UPCOMING NEARBY EVENTS")
        end

        it "logs HA service failures appropriately" do
          allow(Rails.logger).to receive(:warn).and_call_original
          context_builder.send(:get_current_location)
          expect(Rails.logger).to have_received(:warn).with(/Failed to get current location/)
        end
      end
    end

    # NOTE: The "integration with full RAG context" describe block was removed.
    # It exercised PromptService#inject_rag_context and the inline similarity-search
    # RAG injection ("Recent relevant conversations"), which were deleted in the
    # refactor (RAG/similarity injection is commented out in
    # Prompts::SystemContextEnhancer). There is no replacement method to test, so the
    # examples were not portable.

    describe "full prompt building with proactive events" do
      let!(:imminent_event) do
        create(:event,
               title: "Gate Closure Warning",
               description: "Gate closing in 4 hours - last chance to enter/exit",
               event_time: 4.hours.from_now,
               importance: 10)
      end

      it "includes proactive events in complete prompt context" do
        allow(HaDataSync).to receive(:extended_location).and_return(nil)

        prompt_data = prompt_service.build
        context = prompt_data[:context]

        expect(context).to include("UPCOMING HIGH-PRIORITY EVENTS")
        expect(context).to include("Gate Closure Warning")
        # NOTE: relative-time strings ("4 hours") and the
        # "VERY IMPORTANT BREAKING NEWS"/"Random Facts" context blocks were removed
        # in the refactor, so those assertions were dropped.
      end

      it "maintains context structure with proactive events" do
        prompt_data = prompt_service.build

        expect(prompt_data).to have_key(:system_prompt)
        expect(prompt_data).to have_key(:messages)
        expect(prompt_data).to have_key(:context)
        expect(prompt_data).to have_key(:tools)

        context = prompt_data[:context]
        expect(context).to be_a(String)
        expect(context.length).to be > 100 # Should have substantial content
      end
    end

    describe "time-based event filtering" do
      # Distinct titles are required because the factory defaults all events to the
      # same title, and the refactored ContextBuilder no longer emits relative-time
      # strings (it formats absolute timestamps), so we assert on titles instead.
      let!(:immediate_event) { create(:event, title: "Immediate Event", event_time: 1.hour.from_now, importance: 8) }
      let!(:near_future_event) { create(:event, title: "Near Future Event", event_time: 24.hours.from_now, importance: 8) }
      let!(:far_future_event) { create(:event, title: "Far Future Event", event_time: 3.days.from_now, importance: 8) }
      let!(:past_event) { create(:event, title: "Past Event", event_time: 2.hours.ago, importance: 9) }

      it "only includes events within 48-hour window" do
        allow(HaDataSync).to receive(:extended_location).and_return(nil)
        context = context_builder.send(:build_upcoming_events_context)

        expect(context).to include("Immediate Event")
        expect(context).to include("Near Future Event")
        expect(context).not_to include("Far Future Event")  # outside 48h window
        expect(context).not_to include("Past Event")        # already happened
      end
    end

    describe "event importance filtering" do
      let!(:critical_event) { create(:event, title: "Critical Event", event_time: 6.hours.from_now, importance: 10) }
      let!(:high_event) { create(:event, title: "High Event", event_time: 8.hours.from_now, importance: 7) }
      let!(:medium_event) { create(:event, title: "Medium Event", event_time: 4.hours.from_now, importance: 6) }
      let!(:low_event) { create(:event, title: "Low Event", event_time: 2.hours.from_now, importance: 3) }

      it "only includes high importance events (>= 7)" do
        allow(HaDataSync).to receive(:extended_location).and_return(nil)
        context = context_builder.send(:build_upcoming_events_context)

        # Should include importance >= 7
        expect(context).to include("Critical Event")
        expect(context).to include("High Event")

        # Should exclude importance < 7
        expect(context).not_to include("Medium Event")
        expect(context).not_to include("Low Event")
      end
    end

    describe "no events scenario" do
      before { allow(HaDataSync).to receive(:extended_location).and_return(nil) }

      it "returns nil when no high-priority events exist" do
        # Only create low-priority events
        create(:event, event_time: 2.hours.from_now, importance: 3)
        create(:event, event_time: 4.hours.from_now, importance: 5)

        context = context_builder.send(:build_upcoming_events_context)
        expect(context).to be_nil
      end

      it "handles empty event database gracefully" do
        Event.destroy_all

        expect { context_builder.send(:build_upcoming_events_context) }.not_to raise_error
        context = context_builder.send(:build_upcoming_events_context)
        expect(context).to be_nil
      end
    end
  end
end
