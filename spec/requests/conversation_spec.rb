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
  end
end