require 'rails_helper'

RSpec.describe "Conversation API", type: :request do
  describe "POST /api/v1/conversation" do
    let(:hass_payload) do
      JSON.parse(File.read(Rails.root.join('spec/fixtures/hass_conversation_request.json')))
    end


    it "handles Home Assistant conversation requests", :vcr do
      # Mock the orchestrator so the test doesn't depend on external API calls
      mock_orchestrator_result = mock_orchestrator_success(
        speech_text: "I understand you're asking what's going on."
      )
      stub_orchestrator_call(mock_orchestrator_result)

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
      # Mock the persona API call that Setup makes
      allow(HomeAssistantService).to receive(:entity).with("input_select.current_persona")
        .and_return({ "state" => "sparkle" })

      # Test the setup behavior directly rather than trying to mock the full flow
      session_id = hass_payload.dig('context', 'session_id')
      context = {
        conversation_id: hass_payload.dig('context', 'conversation_id'),
        device_id: hass_payload.dig('context', 'device_id'),
        language: hass_payload.dig('context', 'language'),
        voice_interaction: hass_payload.dig('context', 'voice_interaction'),
        timestamp: hass_payload.dig('context', 'timestamp'),
        ha_context: hass_payload.dig('context', 'ha_context'),
        agent_id: hass_payload.dig('context', 'ha_context', 'agent_id'),
        source: "hass_conversation"
      }

      expect {
        setup_result = ConversationNewOrchestrator::Setup.call(session_id: session_id, context: context)
        unless setup_result.success?
          puts "Setup failed: #{setup_result.error}"
        end
        expect(setup_result.success?).to be true
      }.to change(Conversation, :count).by(1)

      conversation = Conversation.last
      expect(conversation.session_id).to eq('voice_01K2X8DA2CA7Z2Q2R8F4HNFRB7')
      expect(conversation.source).to eq('api') # default value from migration
    end

    it "extracts agent_id from ha_context", :vcr do
      # Mock the persona API call that Setup makes
      allow(HomeAssistantService).to receive(:entity).with("input_select.current_persona")
        .and_return({ "state" => "sparkle" })

      # Test that setup properly extracts and stores agent_id from ha_context
      session_id = hass_payload.dig('context', 'session_id')
      context = {
        conversation_id: hass_payload.dig('context', 'conversation_id'),
        device_id: hass_payload.dig('context', 'device_id'),
        language: hass_payload.dig('context', 'language'),
        voice_interaction: hass_payload.dig('context', 'voice_interaction'),
        timestamp: hass_payload.dig('context', 'timestamp'),
        ha_context: hass_payload.dig('context', 'ha_context'),
        agent_id: hass_payload.dig('context', 'ha_context', 'agent_id'),
        source: "hass_conversation"
      }

      setup_result = ConversationNewOrchestrator::Setup.call(session_id: session_id, context: context)
      expect(setup_result.success?).to be true

      # Check that agent_id is extracted and could be used for persona switching
      conversation = Conversation.last
      expect(conversation.metadata_json).to include('agent_id')
      expect(conversation.metadata_json['agent_id']).to eq('glitchcube_conversation_01K2C7ETREDK5YDZBQ16RWBE09')
    end

    it "passes continue_conversation flag correctly to Home Assistant", :vcr do
      # Mock the orchestrator to return continue_conversation: true
      mock_orchestrator_result = mock_orchestrator_success(
        speech_text: "Test response that should continue",
        continue_conversation: true
      )

      stub_orchestrator_call(mock_orchestrator_result)

      post '/api/v1/conversation', params: hass_payload, as: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      # This should be true if continue_conversation is correctly passed from orchestrator result
      expect(json_response.dig('data', 'continue_conversation')).to be(true)
    end

    it "stores narrative elements internally but doesn't pass them to Home Assistant", :vcr do
      # Mock the orchestrator to return narrative elements (using legacy format for controller compatibility)
      mock_orchestrator_result = build_legacy_mock_response(
        speech_text: "I'm functioning well, thank you for asking.",
        continue_conversation: false,
        inner_thoughts: "The human seems curious about my systems",
        current_mood: "analytical"
      )

      stub_orchestrator_call(mock_orchestrator_result)

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
