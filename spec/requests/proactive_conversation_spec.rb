require 'rails_helper'

RSpec.describe "Proactive Conversation API", type: :request do
  let(:proactive_result) do
    {
      should_announce: true,
      message: "Hey there! I noticed something interesting happening.",
      persona: "buddy",
      satellite_entity: "assist_satellite.glitchcube"
    }
  end

  before do
    allow(ProactiveMessageService).to receive(:generate).and_return(proactive_result)
    allow(HomeAssistantService).to receive(:call_service).and_return({ "success" => true })
  end

  describe "POST /api/v1/conversation/proactive" do
    it "handles proactive conversation with trigger and context" do
      payload = {
        trigger: "motion_detected_with_boredom",
        context: "Motion in living room, no conversation for 22 minutes"
      }

      post '/api/v1/conversation/proactive', params: payload, as: :json

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response['success']).to be(true)
      expect(json_response['persona']).to eq('buddy')
      expect(json_response['message']).to be_present
    end

    it "passes trigger and context to ProactiveMessageService" do
      payload = {
        trigger: "loneliness_check",
        context: "User is home but no interaction for 65 minutes, feeling lonely"
      }

      expect(ProactiveMessageService).to receive(:generate).with(
        trigger_type: "loneliness_check",
        context: "User is home but no interaction for 65 minutes, feeling lonely"
      ).and_return(proactive_result)

      post '/api/v1/conversation/proactive', params: payload, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['success']).to be(true)
    end

    it "handles missing parameters gracefully — defaults trigger to 'unknown_trigger'" do
      expect(ProactiveMessageService).to receive(:generate).with(
        trigger_type: "unknown_trigger",
        context: {}
      ).and_return(proactive_result)

      post '/api/v1/conversation/proactive', params: {}, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['success']).to be(true)
    end

    it "skips announcement when ProactiveMessageService says not to announce" do
      allow(ProactiveMessageService).to receive(:generate).and_return({
        should_announce: false,
        message: nil,
        persona: nil,
        satellite_entity: nil
      })

      post '/api/v1/conversation/proactive', params: { trigger: "quiet_time" }, as: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['success']).to be(true)
      expect(json_response['skipped']).to be(true)
    end

    it "calls HomeAssistantService with the satellite entity and message" do
      payload = { trigger: "user_arrived_home", context: "Front door sensor triggered" }

      expect(HomeAssistantService).to receive(:call_service).with(
        "assist_satellite",
        "start_conversation",
        hash_including(
          entity_id: "assist_satellite.glitchcube",
          start_message: "Hey there! I noticed something interesting happening."
        )
      ).and_return({ "success" => true })

      post '/api/v1/conversation/proactive', params: payload, as: :json

      expect(response).to have_http_status(:ok)
    end

    it "handles different types of proactive triggers" do
      test_cases = [
        { trigger: "weather_alert", context: "Storm approaching" },
        { trigger: "security_event", context: "Door left open" },
        { trigger: "system_status", context: "Battery backup activated" },
        { trigger: "schedule_reminder", context: "Calendar shows meeting" }
      ]

      test_cases.each do |test_case|
        post '/api/v1/conversation/proactive', params: test_case, as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['success']).to be(true)
      end
    end

    it "returns persona and message from ProactiveMessageService result" do
      allow(ProactiveMessageService).to receive(:generate).and_return({
        should_announce: true,
        message: "The stars are beautiful tonight!",
        persona: "zorp",
        satellite_entity: "assist_satellite.glitchcube"
      })

      post '/api/v1/conversation/proactive', params: { trigger: "stargazing_time" }, as: :json

      json_response = JSON.parse(response.body)
      expect(json_response['success']).to be(true)
      expect(json_response['persona']).to eq('zorp')
      expect(json_response['message']).to eq('The stars are beautiful tonight!')
    end
  end

  describe "Golden path end-to-end test" do
    it "complete proactive conversation flow with realistic scenario" do
      payload = {
        trigger: "motion_detected_with_boredom",
        context: "Motion detected in living room. No interaction for 30 minutes."
      }

      post '/api/v1/conversation/proactive', params: payload, as: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response['success']).to be(true)
      expect(json_response['persona']).to eq('buddy')
      expect(json_response['message']).to be_present
      expect(json_response['message'].length).to be > 5
    end
  end
end
