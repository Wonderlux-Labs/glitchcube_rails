# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorldStateUpdaters::ConversationSummarizerService, type: :service do
  describe "enhanced summarizer with real LLM API", :vcr do
    let!(:conversation) { create(:conversation, session_id: "test_session_123") }
    let!(:log1) do
      create(:conversation_log,
             conversation: conversation,
             user_message: "Hey, I'm planning to go to the Temple Burn tonight with Sarah. She's great at fire spinning!",
             ai_response: "That sounds amazing! The Temple Burn is always such a powerful experience. Fire spinning adds such beauty to the ceremony.")
    end
    let!(:log2) do
      create(:conversation_log,
             conversation: conversation,
             user_message: "Yeah, we should meet at 8 PM near the Temple. It's going to be a 9/10 importance event for me.",
             ai_response: "Perfect timing! I'll make sure to remind you. The Temple holds so much meaning for everyone at Burning Man.")
    end

    before do
      conversation.update!(ended_at: Time.current)
    end

    describe "with real API call to enhanced model" do
      it "extracts people and events using configured summarizer model", vcr: { cassette_name: "enhanced_conversation_summarizer/extract_people_and_events" } do
        service = described_class.new([conversation.id])
        
        expect {
          summary = service.call
          expect(summary).to be_persisted
          expect(summary.summary_type).to eq("hourly")
          
          # Verify enhanced extraction
          metadata = summary.metadata_json
          expect(metadata["people_extracted"]).to be > 0
          expect(metadata["events_extracted"]).to be > 0
          expect(metadata["topics"]).to be_an(Array)
        }.to change(Summary, :count).by(1)
      end

      it "creates Person records from extracted data", vcr: { cassette_name: "enhanced_conversation_summarizer/create_person_records" } do
        service = described_class.new([conversation.id])
        
        expect {
          service.call
        }.to change(Person, :count).by_at_least(1)
        
        sarah = Person.find_by(name: "Sarah")
        expect(sarah).to be_present
        expect(sarah.description).to include("fire spinning")
        expect(sarah.extracted_from_session).to eq([conversation.id].join(","))
      end

      it "creates Event records from extracted data", vcr: { cassette_name: "enhanced_conversation_summarizer/create_event_records" } do
        service = described_class.new([conversation.id])
        
        expect {
          service.call
        }.to change(Event, :count).by_at_least(1)
        
        temple_burn = Event.find_by("title ILIKE ?", "%temple%burn%")
        expect(temple_burn).to be_present
        expect(temple_burn.description).to include("ceremony")
        expect(temple_burn.importance).to eq(9) # Should extract 9/10 -> 9
        expect(temple_burn.extracted_from_session).to eq([conversation.id].join(","))
      end
    end

    describe "with different conversation patterns" do
      let!(:tech_conversation) { create(:conversation, session_id: "tech_session_456") }
      let!(:tech_log) do
        create(:conversation_log,
               conversation: tech_conversation,
               user_message: "The cube's lights are acting up. Can you help debug this issue?",
               ai_response: "Let me check the light system status and run some diagnostics.")
      end

      before do
        tech_conversation.update!(ended_at: Time.current)
      end

      it "handles technical conversations appropriately", vcr: { cassette_name: "enhanced_conversation_summarizer/technical_conversation" } do
        service = described_class.new([tech_conversation.id])
        summary = service.call
        
        expect(summary.summary_text).to include("debug")
        expect(summary.metadata_json["topics"]).to include("technical")
      end
    end

    describe "error handling with real API" do
      before do
        # Test with malformed conversation data
        allow_any_instance_of(described_class).to receive(:format_conversations_for_prompt).and_return("INVALID JSON PROMPT")
      end

      it "handles API errors gracefully", vcr: { cassette_name: "enhanced_conversation_summarizer/api_error_handling" } do
        service = described_class.new([conversation.id])
        
        expect { service.call }.not_to raise_error
        
        summary = Summary.last
        expect(summary.summary_text).to include("Failed to parse")
      end
    end

    describe "model configuration" do
      it "uses the configured summarizer model" do
        expect(Rails.configuration.summarizer_model).to eq("openai/gpt-oss-120b")
        
        service = described_class.new([conversation.id])
        
        expect(LlmService).to receive(:generate_text).with(
          hash_including(model: "openai/gpt-oss-120b")
        ).and_call_original
        
        service.call
      end
    end

    describe "time parsing with real extraction" do
      let!(:time_conversation) { create(:conversation, session_id: "time_session") }
      let!(:time_log) do
        create(:conversation_log,
               conversation: time_conversation,
               user_message: "Don't forget about the sunrise yoga tomorrow morning at 6 AM at Center Camp!",
               ai_response: "I'll set a reminder for the sunrise yoga session. That sounds wonderful!")
      end

      before do
        time_conversation.update!(ended_at: Time.current)
      end

      it "parses various time formats from extracted events", vcr: { cassette_name: "enhanced_conversation_summarizer/time_parsing" } do
        service = described_class.new([time_conversation.id])
        service.call
        
        yoga_event = Event.find_by("title ILIKE ?", "%yoga%")
        if yoga_event
          expect(yoga_event.event_time).to be_present
          expect(yoga_event.event_time.hour).to eq(6) # Should parse 6 AM
        end
      end
    end
  end

  describe "batch processing with VCR" do
    let!(:conversation1) { create(:conversation, session_id: "batch_1") }
    let!(:conversation2) { create(:conversation, session_id: "batch_2") }
    
    before do
      create(:conversation_log, conversation: conversation1, 
             user_message: "Going to art walk with Alice", 
             ai_response: "Have fun exploring!")
      create(:conversation_log, conversation: conversation2, 
             user_message: "Meeting Bob for dinner at 7 PM", 
             ai_response: "Enjoy your meal!")
      
      conversation1.update!(ended_at: Time.current)
      conversation2.update!(ended_at: Time.current)
    end

    it "processes multiple conversations in one API call", vcr: { cassette_name: "enhanced_conversation_summarizer/batch_processing" } do
      service = described_class.new([conversation1.id, conversation2.id])
      
      expect {
        summary = service.call
        
        # Should create multiple people and events from batch
        metadata = summary.metadata_json
        expect(metadata["people_extracted"]).to be >= 2  # Alice and Bob
        expect(metadata["conversations_count"]).to eq(2)
      }.to change(Person, :count).by_at_least(2)
    end
  end
end