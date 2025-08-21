# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Proactive Events Integration", type: :integration do
  describe "PromptService proactive event injection" do
    let(:prompt_service) do
      PromptService.new(
        persona: "buddy",
        conversation: create(:conversation),
        extra_context: {},
        user_message: "What's happening today?"
      )
    end

    describe "#inject_upcoming_events_context" do
      context "with high-priority upcoming events" do
        let!(:high_priority_event) do
          create(:event,
                 title: "Temple Burn",
                 description: "Sacred ceremony at the Temple",
                 event_time: 6.hours.from_now,
                 importance: 9,
                 location: "Temple")
        end

        let!(:medium_priority_event) do
          create(:event,
                 title: "Art Walk",
                 description: "Casual art exploration",
                 event_time: 4.hours.from_now,
                 importance: 5,
                 location: "Deep Playa")
        end

        it "injects high-priority events regardless of user query" do
          context = prompt_service.send(:inject_upcoming_events_context)
          
          expect(context).to include("UPCOMING HIGH-PRIORITY EVENTS")
          expect(context).to include("Temple Burn")
          expect(context).not_to include("Art Walk")  # Only importance >= 7
        end

        it "formats event context properly" do
          context = prompt_service.send(:inject_upcoming_events_context)
          
          expect(context).to include("Sacred ceremony at the Temple")
          expect(context).to match(/upcoming.*\d{2}\/\d{2} at \d{2}:\d{2} [AP]M/)
        end
      end

      context "with location-based events" do
        let!(:nearby_event) do
          create(:event,
                 title: "Camp Party",
                 description: "Fun at our neighbor camp",
                 event_time: 2.hours.from_now,
                 importance: 6,
                 location: "Black Rock City")
        end

        let!(:distant_event) do
          create(:event,
                 title: "Reno Event",
                 description: "Something in Reno",
                 event_time: 2.hours.from_now,
                 importance: 6,
                 location: "Reno")
        end

        before do
          # Mock current location as Black Rock City
          ha_service = double("HomeAssistantService")
          allow(HomeAssistantService).to receive(:new).and_return(ha_service)
          
          context_sensor = {
            "attributes" => {
              "current_location" => "Black Rock City"
            }
          }
          allow(ha_service).to receive(:entity).with("sensor.glitchcube_context").and_return(context_sensor)
        end

        it "injects nearby events when location is available" do
          context = prompt_service.send(:inject_upcoming_events_context)
          
          expect(context).to include("UPCOMING NEARBY EVENTS")
          expect(context).to include("Camp Party")
          expect(context).not_to include("Reno Event")
        end
      end

      context "with no relevant events" do
        it "returns nil when no events match criteria" do
          context = prompt_service.send(:inject_upcoming_events_context)
          expect(context).to be_nil
        end
      end

      context "when location service fails" do
        before do
          allow(HomeAssistantService).to receive(:new).and_raise(StandardError.new("HA unavailable"))
        end

        it "continues without nearby events" do
          expect { prompt_service.send(:inject_upcoming_events_context) }.not_to raise_error
        end

        it "logs location retrieval failure" do
          prompt_service.send(:get_current_location)
          expect(Rails.logger).to have_received(:warn).with(/Failed to get current location/)
        end
      end
    end

    describe "integration with RAG context injection" do
      let!(:high_priority_event) do
        create(:event,
               title: "Main Event",
               description: "The big show everyone's waiting for",
               event_time: 12.hours.from_now,
               importance: 10)
      end

      let!(:relevant_summary) do
        create(:summary, summary_text: "Previous discussion about events")
      end

      before do
        # Mock similarity search to return relevant summary
        allow(Summary).to receive(:similarity_search).and_return([relevant_summary])
        allow(Event).to receive(:similarity_search).and_return([])
        allow(Person).to receive(:similarity_search).and_return([])
      end

      it "includes both proactive events and RAG results" do
        context = prompt_service.send(:inject_rag_context, "What events are coming up?")
        
        expect(context).to include("UPCOMING HIGH-PRIORITY EVENTS")
        expect(context).to include("Main Event")
        expect(context).to include("Recent relevant conversations")
        expect(context).to include("Previous discussion about events")
      end

      it "prioritizes proactive events by placing them first" do
        context = prompt_service.send(:inject_rag_context, "Tell me about events")
        lines = context.split("\n")
        
        high_priority_line = lines.find_index { |line| line.include?("HIGH-PRIORITY EVENTS") }
        conversation_line = lines.find_index { |line| line.include?("Recent relevant") }
        
        expect(high_priority_line).to be < conversation_line
      end
    end

    describe "full prompt building with proactive events" do
      let!(:urgent_event) do
        create(:event,
               title: "Emergency Exodus",
               description: "Critical evacuation information",
               event_time: 30.minutes.from_now,
               importance: 10)
      end

      it "includes proactive events in full prompt context" do
        prompt_data = prompt_service.build
        context = prompt_data[:context]
        
        expect(context).to include("UPCOMING HIGH-PRIORITY EVENTS")
        expect(context).to include("Emergency Exodus")
        expect(context).to include("30 minutes")
      end

      it "maintains other context elements alongside proactive events" do
        prompt_data = prompt_service.build
        context = prompt_data[:context]
        
        expect(context).to include("UPCOMING HIGH-PRIORITY EVENTS")
        expect(context).to include("VERY IMPORTANT BREAKING NEWS")
        expect(context).to include("Random Facts")
      end
    end
  end

  describe "Event scoping for proactive injection" do
    let!(:past_high_event) { create(:event, event_time: 1.hour.ago, importance: 9) }
    let!(:future_low_event) { create(:event, event_time: 1.hour.from_now, importance: 3) }
    let!(:future_high_event) { create(:event, event_time: 1.hour.from_now, importance: 8) }
    let!(:far_future_high_event) { create(:event, event_time: 3.days.from_now, importance: 9) }

    it "only includes upcoming high-importance events within time window" do
      high_priority_events = Event.upcoming.high_importance.within_hours(48).limit(3)
      
      expect(high_priority_events).to include(future_high_event)
      expect(high_priority_events).not_to include(past_high_event)        # Past
      expect(high_priority_events).not_to include(future_low_event)       # Low importance
      expect(high_priority_events).not_to include(far_future_high_event)  # Outside 48h window
    end

    it "respects location filtering for nearby events" do
      camp_event = create(:event, event_time: 2.hours.from_now, location: "Camp Area", importance: 5)
      playa_event = create(:event, event_time: 2.hours.from_now, location: "Deep Playa", importance: 5)
      
      nearby_events = Event.upcoming.by_location("Camp Area").within_hours(24).limit(2)
      
      expect(nearby_events).to include(camp_event)
      expect(nearby_events).not_to include(playa_event)
    end
  end
end