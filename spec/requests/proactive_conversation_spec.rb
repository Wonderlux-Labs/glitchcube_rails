require 'rails_helper'

RSpec.describe "Proactive Conversation API", type: :request do
  describe "POST /api/v1/conversation/proactive" do
    it "handles proactive conversation with trigger and context", :vcr do
      payload = {
        trigger: "motion_detected_with_boredom",
        context: "Motion in living room, no conversation for 22 minutes"
      }

      post '/api/v1/conversation/proactive', params: payload, as: :json

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response).to have_key('success')
      expect(json_response).to have_key('data')
      expect(json_response['success']).to be(true)

      # Should have response data
      expect(json_response['data']).to have_key('response_type')
      expect(json_response['data']).to have_key('speech_text')
      expect(json_response['data']['speech_text']).to be_present

      # Should include continue_conversation flag
      expect(json_response['data']).to have_key('continue_conversation')
    end

    it "creates conversation record for proactive trigger", :vcr do
      payload = {
        trigger: "loneliness_check",
        context: "User is home but no interaction for 65 minutes, feeling lonely"
      }

      expect {
        post '/api/v1/conversation/proactive', params: payload, as: :json
      }.to change(Conversation, :count).by(1)

      conversation = Conversation.last
      expect(conversation.source).to eq('api')
      expect(conversation.session_id).to be_present
      # Session ID should be the default proactive session ID since no specific one was provided
    end

    it "handles missing parameters gracefully", :vcr do
      # Send with no trigger or context
      post '/api/v1/conversation/proactive', params: {}, as: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['success']).to be(true)

      # Should still get a response even with defaults
      expect(json_response['data']['speech_text']).to be_present
    end

    it "handles proactive conversation that might trigger actions", :vcr do
      # Mock a proactive trigger that might cause light changes
      allow_any_instance_of(ConversationOrchestrator).to receive(:call).and_return({
        continue_conversation: false,
        response: {
          speech: {
            plain: {
              speech: "I noticed you're back! Let me brighten things up a bit.",
              extra_data: {
                async_tools_queued: [ 'set_light_color_and_brightness' ]
              }
            }
          }
        }
      })

      payload = {
        trigger: "user_arrived_home",
        context: "Front door sensor triggered, lights were dim"
      }

      post '/api/v1/conversation/proactive', params: payload, as: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      # Should indicate background tools were queued
      expect(json_response['data']['response_type']).to eq('immediate_speech_with_background_tools')
    end

    it "handles different types of proactive triggers", :vcr do
      test_cases = [
        {
          trigger: "weather_alert",
          context: "Storm approaching, might want to secure outdoor items"
        },
        {
          trigger: "security_event",
          context: "Door left open for 10 minutes while away"
        },
        {
          trigger: "system_status",
          context: "Battery backup activated, main power lost"
        },
        {
          trigger: "schedule_reminder",
          context: "Calendar shows meeting in 15 minutes"
        }
      ]

      test_cases.each do |test_case|
        post '/api/v1/conversation/proactive', params: test_case, as: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be(true)
        expect(json_response['data']['speech_text']).to be_present
      end
    end

    it "formats proactive message correctly for orchestrator" do
      # Test that the message is properly formatted with [PROACTIVE] prefix
      orchestrator_instance = instance_double(ConversationOrchestrator)
      allow(ConversationOrchestrator).to receive(:new).with(
        hash_including(
          message: "[PROACTIVE] motion_detected_with_boredom: Motion in living room, no conversation for 22 minutes"
        )
      ).and_return(orchestrator_instance)

      allow(orchestrator_instance).to receive(:call).and_return({
        continue_conversation: false,
        response: {
          speech: {
            plain: {
              speech: "I understand the motion detected situation."
            }
          }
        }
      })

      payload = {
        trigger: "motion_detected_with_boredom",
        context: "Motion in living room, no conversation for 22 minutes"
      }

      post '/api/v1/conversation/proactive', params: payload, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "includes proactive context information" do
      # Test that proactive context is properly structured
      orchestrator_instance = instance_double(ConversationOrchestrator)
      allow(ConversationOrchestrator).to receive(:new).with(
        hash_including(
          context: hash_including(
            source: "proactive_trigger",
            trigger: "test_trigger",
            context: "test context",
            device_id: "cube_proactive_system"
          )
        )
      ).and_return(orchestrator_instance)

      allow(orchestrator_instance).to receive(:call).and_return({
        continue_conversation: false,
        response: {
          speech: {
            plain: {
              speech: "Test response for proactive context."
            }
          }
        }
      })

      payload = {
        trigger: "test_trigger",
        context: "test context"
      }

      post '/api/v1/conversation/proactive', params: payload, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "Golden path end-to-end test" do
    it "complete proactive conversation flow with realistic scenario", :vcr do
      # Simulate: Motion detected after 30 minutes of no interaction
      payload = {
        trigger: "motion_detected_with_boredom",
        context: "Motion detected in living room. Systems report no interaction for 30 minutes. Boredom levels rising. Motion suggests human presence nearby."
      }

      # Make the proactive conversation request
      post '/api/v1/conversation/proactive', params: payload, as: :json

      # Debug output if the response failed
      if response.status != 200
        puts "Response status: #{response.status}"
        puts "Response body: #{response.body}"
        puts "Response headers: #{response.headers.to_h}"
      end

      # Verify successful response
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      # Verify response structure
      expect(json_response['success']).to be(true)
      expect(json_response['data']).to be_a(Hash)

      # Should have speech response
      speech_text = json_response.dig('data', 'speech_text')
      expect(speech_text).to be_present
      expect(speech_text.length).to be > 10  # Should be a real response

      # Should have response type
      response_type = json_response.dig('data', 'response_type')
      expect(response_type).to be_in([ 'normal', 'immediate_speech_with_background_tools' ])

      # Should have continue conversation flag
      continue_conversation = json_response.dig('data', 'continue_conversation')
      expect([ true, false ]).to include(continue_conversation)

      # Should have metadata
      expect(json_response.dig('data', 'metadata')).to be_a(Hash)

      # Verify conversation was logged
      conversation = Conversation.last
      expect(conversation).to be_present
      expect(conversation.source).to eq('api')

      # Check the conversation log for the actual message content
      conversation_log = ConversationLog.where(session_id: conversation.session_id).last
      expect(conversation_log).to be_present
      expect(conversation_log.user_message).to include('[PROACTIVE]')
      expect(conversation_log.user_message).to include('motion_detected_with_boredom')
      expect(conversation_log.user_message).to include('30 minutes')
      expect(conversation_log.ai_response).to be_present

      Rails.logger.info "🎯 Golden path test completed successfully!"
      Rails.logger.info "🤖 Proactive trigger: #{payload[:trigger]}"
      Rails.logger.info "📝 Context: #{payload[:context]}"
      Rails.logger.info "🗣️ AI Response: #{speech_text&.truncate(100)}"
      Rails.logger.info "🔄 Continue conversation: #{continue_conversation}"
      Rails.logger.info "📊 Response type: #{response_type}"
    end
  end
end
