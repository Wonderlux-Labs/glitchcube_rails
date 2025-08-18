require 'rails_helper'

RSpec.describe "Conversation API", type: :request do
  describe "POST /api/v1/conversation" do
    let(:hass_payload) do
      JSON.parse(File.read(Rails.root.join('spec/fixtures/hass_conversation_request.json')))
    end


    it "handles Home Assistant conversation requests", :vcr do
      post '/api/v1/conversation', params: hass_payload, as: :json

      if response.status != 200
        puts "Response status: #{response.status}"
        puts "Response body: #{response.body}"
      end

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response).to have_key('success')
      expect(json_response).to have_key('data')
      expect(json_response['success']).to be(true)
    end

    it "creates conversation with correct session_id", :vcr do
      expect {
        post '/api/v1/conversation', params: hass_payload, as: :json
      }.to change(Conversation, :count).by(1)

      conversation = Conversation.last
      expect(conversation.session_id).to eq('voice_01K2X8DA2CA7Z2Q2R8F4HNFRB7')
      expect(conversation.source).to eq('api')
    end

    it "extracts agent_id from ha_context", :vcr do
      post '/api/v1/conversation', params: hass_payload, as: :json

      # Check that agent_id is extracted and could be used for persona switching
      conversation = Conversation.last
      expect(conversation.metadata_json).to include('agent_id')
      expect(conversation.metadata_json['agent_id']).to eq('glitchcube_conversation_01K2C7ETREDK5YDZBQ16RWBE09')
    end

    it "passes continue_conversation flag correctly to Home Assistant", :vcr do
      # Mock the orchestrator to return continue_conversation: true
      mock_orchestrator_result = {
        continue_conversation: true,
        response: {
          speech: {
            plain: {
              speech: "Test response that should continue"
            }
          }
        }
      }

      allow_any_instance_of(ConversationOrchestrator).to receive(:call).and_return(mock_orchestrator_result)

      post '/api/v1/conversation', params: hass_payload, as: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      # This should be true if continue_conversation is correctly passed from orchestrator result
      expect(json_response.dig('data', 'continue_conversation')).to be(true)
    end

    it "stores narrative elements internally but doesn't pass them to Home Assistant", :vcr do
      # Mock the orchestrator to return narrative elements
      mock_orchestrator_result = {
        continue_conversation: false,
        inner_thoughts: "The human seems curious about my systems",
        current_mood: "analytical",
        response: {
          speech: {
            plain: {
              speech: "I'm functioning well, thank you for asking."
            }
          }
        }
      }

      allow_any_instance_of(ConversationOrchestrator).to receive(:call).and_return(mock_orchestrator_result)

      post '/api/v1/conversation', params: hass_payload, as: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      # Narrative elements should NOT be passed to Home Assistant
      expect(json_response.dig('data', 'inner_thoughts')).to be_nil
      expect(json_response.dig('data', 'current_mood')).to be_nil

      # But continue_conversation should still be passed through
      expect(json_response.dig('data', 'continue_conversation')).to be(false)
    end
  end
end
