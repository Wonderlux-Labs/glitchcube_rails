# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptService, "proactive events with VCR", type: :service do
  describe "proactive event injection with real API context", :vcr do
    let(:conversation) { create(:conversation, session_id: "proactive_test_session") }
    let(:prompt_service) do
      described_class.new(
        persona: "buddy",
        conversation: conversation,
        extra_context: { source: "vcr_proactive_test" },
        user_message: "What's happening today?"
      )
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

      it "injects high-priority events automatically in context", vcr: { cassette_name: "proactive_events/high_priority_injection" } do
        # Mock Home Assistant to avoid external calls in this test
        ha_service = double("HomeAssistantService")
        allow(HomeAssistantService).to receive(:new).and_return(ha_service)
        allow(ha_service).to receive(:entity).and_return(nil)

        context = prompt_service.send(:inject_upcoming_events_context)

        expect(context).to include("UPCOMING HIGH-PRIORITY EVENTS")
        expect(context).to include("Emergency Weather Alert")
        expect(context).to include("Temple Burn Ceremony")
        expect(context).not_to include("Art Walk") # Only importance >= 7

        # Verify timing information is included
        expect(context).to include("2 hours")
        expect(context).to include("8 hours")
      end

      it "formats high-priority events with proper urgency indicators", vcr: { cassette_name: "proactive_events/urgency_formatting" } do
        context = prompt_service.send(:inject_upcoming_events_context)

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
          ha_service = double("HomeAssistantService")
          allow(HomeAssistantService).to receive(:new).and_return(ha_service)

          context_sensor = {
            "attributes" => {
              "current_location" => "Center Camp"
            }
          }
          allow(ha_service).to receive(:entity).with("sensor.glitchcube_context").and_return(context_sensor)
        end

        it "injects nearby events based on current location", vcr: { cassette_name: "proactive_events/nearby_location_injection" } do
          context = prompt_service.send(:inject_upcoming_events_context)

          expect(context).to include("UPCOMING NEARBY EVENTS")
          expect(context).to include("Camp Sunrise Pancake Breakfast")
          expect(context).not_to include("Deep Playa Sound Bath")

          expect(context).to include("next 24h")
          expect(context).to include("Center Camp")
        end

        it "combines high-priority and nearby events correctly", vcr: { cassette_name: "proactive_events/combined_priority_and_nearby" } do
          # Add a high-priority event too
          create(:event,
                 title: "Critical Safety Briefing",
                 importance: 8,
                 event_time: 3.hours.from_now)

          context = prompt_service.send(:inject_upcoming_events_context)

          expect(context).to include("UPCOMING HIGH-PRIORITY EVENTS")
          expect(context).to include("UPCOMING NEARBY EVENTS")
          expect(context).to include("Critical Safety Briefing")
          expect(context).to include("Camp Sunrise Pancake Breakfast")
        end
      end

      context "when location is not available" do
        before do
          ha_service = double("HomeAssistantService")
          allow(HomeAssistantService).to receive(:new).and_return(ha_service)
          allow(ha_service).to receive(:entity).and_return(nil)
        end

        it "only includes high-priority events without location filtering", vcr: { cassette_name: "proactive_events/no_location_available" } do
          context = prompt_service.send(:inject_upcoming_events_context)

          expect(context).not_to include("UPCOMING NEARBY EVENTS")
          # Should not include medium-importance events when no location available
          expect(context).not_to include("Camp Sunrise Pancake Breakfast")
        end
      end

      context "when HA service fails" do
        before do
          allow(HomeAssistantService).to receive(:new).and_raise(StandardError.new("HA connection failed"))
        end

        it "continues gracefully without location-based events", vcr: { cassette_name: "proactive_events/ha_service_failure" } do
          expect { prompt_service.send(:inject_upcoming_events_context) }.not_to raise_error

          context = prompt_service.send(:inject_upcoming_events_context)
          expect(context).not_to include("UPCOMING NEARBY EVENTS")
        end

        it "logs HA service failures appropriately", vcr: { cassette_name: "proactive_events/ha_failure_logging" } do
          prompt_service.send(:get_current_location)
          expect(Rails.logger).to have_received(:warn).with(/Failed to get current location/)
        end
      end
    end

    describe "integration with full RAG context" do
      let!(:high_priority_event) do
        create(:event,
               title: "Exodus Traffic Advisory",
               description: "Heavy traffic expected - plan departure accordingly",
               event_time: 12.hours.from_now,
               importance: 8)
      end

      let!(:relevant_summary) do
        create(:summary,
               summary_text: "Previous conversation about exodus planning and traffic")
      end

      before do
        # Mock similarity search for RAG
        allow(Summary).to receive(:similarity_search).and_return([ relevant_summary ])
        allow(Event).to receive(:similarity_search).and_return([])
        allow(Person).to receive(:similarity_search).and_return([])
      end

      it "includes both proactive events and RAG results in context", vcr: { cassette_name: "proactive_events/full_rag_integration" } do
        context = prompt_service.send(:inject_rag_context, "When should I leave?")

        expect(context).to include("UPCOMING HIGH-PRIORITY EVENTS")
        expect(context).to include("Exodus Traffic Advisory")
        expect(context).to include("Recent relevant conversations")
        expect(context).to include("exodus planning")
      end

      it "prioritizes proactive events before RAG results", vcr: { cassette_name: "proactive_events/event_priority_order" } do
        context = prompt_service.send(:inject_rag_context, "tell me about events")
        lines = context.split("\n")

        high_priority_line = lines.find_index { |line| line.include?("HIGH-PRIORITY EVENTS") }
        conversation_line = lines.find_index { |line| line.include?("Recent relevant") }

        expect(high_priority_line).to be < conversation_line
      end
    end

    describe "full prompt building with proactive events" do
      let!(:imminent_event) do
        create(:event,
               title: "Gate Closure Warning",
               description: "Gate closing in 4 hours - last chance to enter/exit",
               event_time: 4.hours.from_now,
               importance: 10)
      end

      it "includes proactive events in complete prompt context", vcr: { cassette_name: "proactive_events/full_prompt_integration" } do
        prompt_data = prompt_service.build
        context = prompt_data[:context]

        expect(context).to include("UPCOMING HIGH-PRIORITY EVENTS")
        expect(context).to include("Gate Closure Warning")
        expect(context).to include("4 hours")

        # Should also include other context elements
        expect(context).to include("VERY IMPORTANT BREAKING NEWS")
        expect(context).to include("Random Facts")
      end

      it "maintains context structure with proactive events", vcr: { cassette_name: "proactive_events/context_structure" } do
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
      let!(:immediate_event) { create(:event, event_time: 1.hour.from_now, importance: 8) }
      let!(:near_future_event) { create(:event, event_time: 24.hours.from_now, importance: 8) }
      let!(:far_future_event) { create(:event, event_time: 3.days.from_now, importance: 8) }
      let!(:past_event) { create(:event, event_time: 2.hours.ago, importance: 9) }

      it "only includes events within 48-hour window", vcr: { cassette_name: "proactive_events/time_window_filtering" } do
        context = prompt_service.send(:inject_upcoming_events_context)

        expect(context).to include("1 hour")      # immediate_event
        expect(context).to include("24 hours")    # near_future_event
        expect(context).not_to include("3 days")  # far_future_event (outside window)
        expect(context).not_to include("2 hours ago") # past_event (already happened)
      end
    end

    describe "event importance filtering" do
      let!(:critical_event) { create(:event, event_time: 6.hours.from_now, importance: 10) }
      let!(:high_event) { create(:event, event_time: 8.hours.from_now, importance: 7) }
      let!(:medium_event) { create(:event, event_time: 4.hours.from_now, importance: 6) }
      let!(:low_event) { create(:event, event_time: 2.hours.from_now, importance: 3) }

      it "only includes high importance events (>= 7)", vcr: { cassette_name: "proactive_events/importance_filtering" } do
        context = prompt_service.send(:inject_upcoming_events_context)

        # Should include importance >= 7
        expect(context.scan(/\d+ hours/).length).to eq(2) # critical_event and high_event

        # Verify it's not just counting - check it includes the high importance ones
        expect(context).to include("6 hours")  # critical_event
        expect(context).to include("8 hours")  # high_event
      end
    end

    describe "no events scenario" do
      it "returns nil when no high-priority events exist", vcr: { cassette_name: "proactive_events/no_events_scenario" } do
        # Only create low-priority events
        create(:event, event_time: 2.hours.from_now, importance: 3)
        create(:event, event_time: 4.hours.from_now, importance: 5)

        context = prompt_service.send(:inject_upcoming_events_context)
        expect(context).to be_nil
      end

      it "handles empty event database gracefully", vcr: { cassette_name: "proactive_events/empty_database" } do
        Event.destroy_all

        expect { prompt_service.send(:inject_upcoming_events_context) }.not_to raise_error
        context = prompt_service.send(:inject_upcoming_events_context)
        expect(context).to be_nil
      end
    end
  end
end
