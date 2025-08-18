require 'rails_helper'

RSpec.describe 'Real End-to-End Conversation Integration', type: :request do
  let(:session_id) { 'real_e2e_test_session_456' }

  let(:request_payload) do
    {
      text: message,
      context: {
        session_id: session_id,
        device_id: 'test_cube_device',
        ha_context: {
          agent_id: 'cube_conversation'
        }
      }
    }
  end

  before do
    # Clean slate for each test
    Conversation.destroy_all
    ConversationLog.destroy_all

    # Enable two-tier mode
    Rails.configuration.two_tier_tools_enabled = true
    Rails.configuration.tool_calling_model = 'mistralai/mistral-small-3.2-24b-instruct'
    Rails.configuration.default_ai_model = 'openai/gpt-oss-120b'

    # NO MOCKS - test the real system
    # CubePersona.current_persona will call actual HomeAssistant
    # HomeAssistantService will make real API calls
    # Tools will execute against real Home Assistant instance
  end

  describe 'Complete Two-Tier Flow with Real Home Assistant' do
    context 'when controlling cube lights', skip: 'Requires real HA connection and API keys' do
      let(:message) { 'Make the inner cube glow warm orange like a sunset' }

      it 'executes complete end-to-end flow: persona -> narrative LLM -> tool intents -> technical LLM -> HA calls -> speech' do
        puts "\n🚀 Starting REAL end-to-end test..."
        puts "   Session: #{session_id}"
        puts "   Message: #{message}"
        puts "   Payload: #{request_payload.inspect}"

        # Make the actual API call
        post '/api/v1/conversation', params: request_payload

        puts "\n📊 Response Analysis:"
        puts "   Status: #{response.status}"
        puts "   Headers: #{response.headers['Content-Type']}"

        # Should succeed
        expect(response).to have_http_status(:ok)
        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be(true)

        response_data = response_body['data']
        puts "   Success: #{response_body['success']}"
        puts "   Response: #{response_data['response']}"
        puts "   Continue: #{response_data['continue_conversation']}"

        # Validate response structure
        expect(response_data).to have_key('response')
        expect(response_data).to have_key('continue_conversation')
        expect(response_data).to have_key('metadata')

        # Check persona was retrieved from real HA
        puts "\n🎭 Persona Validation:"
        actual_persona = CubePersona.current_persona
        puts "   Current persona: #{actual_persona}"
        expect(actual_persona).to be_in([ :buddy, :jax, :zorp ])

        # Check conversation was created with proper session
        conversation = Conversation.find_by(session_id: session_id)
        expect(conversation).to be_present
        expect(conversation.persona).to eq(actual_persona.to_s)
        puts "   Conversation created: #{conversation.id}"
        puts "   Persona set to: #{conversation.persona}"

        # Check conversation log was created
        log = ConversationLog.find_by(session_id: session_id)
        expect(log).to be_present
        expect(log.user_message).to eq(message)
        expect(log.ai_response).to be_present
        puts "   Log created: #{log.id}"
        puts "   AI response: #{log.ai_response.first(100)}..."

        # Parse metadata to understand what happened
        metadata = JSON.parse(log.metadata)
        puts "\n🔧 Tool Execution Analysis:"
        puts "   Model used: #{metadata['model_used']}"
        puts "   Sync tools: #{metadata['sync_tools']}"
        puts "   Async tools: #{metadata['async_tools']}"
        puts "   Query tools: #{metadata['query_tools']}"
        puts "   Action tools: #{metadata['action_tools']}"

        # In two-tier mode, should show tool activity
        total_tools = (metadata['sync_tools'] || []).length +
                     (metadata['async_tools'] || []).length +
                     (metadata['query_tools'] || []).length +
                     (metadata['action_tools'] || []).length

        if Rails.configuration.two_tier_tools_enabled
          puts "   Two-tier mode: ENABLED"

          # Should have narrative response from persona
          expect(response_data['response']).not_to eq("I understand.")
          expect(response_data['response']).to include_any_of([ 'light', 'orange', 'warm', 'glow', 'cube' ])

          # Should have tool intents processed
          expect(total_tools).to be > 0, "Expected tools to be executed for lighting control"
        else
          puts "   Legacy mode: Using direct tool calls"
        end

        puts "\n✅ End-to-End Test Results:"
        puts "   ✓ API call successful (#{response.status})"
        puts "   ✓ Persona retrieved from HA: #{actual_persona}"
        puts "   ✓ Conversation created with session #{session_id}"
        puts "   ✓ Speech generated: '#{response_data['response']}'"
        puts "   ✓ Tools executed: #{total_tools} total"
        puts "   ✓ Metadata recorded for debugging"

        # Validate that the response makes sense for the persona
        case actual_persona
        when :buddy
          expect(response_data['response']).to match(/friendly|warm|cozy|nice|sure/i)
        when :jax
          expect(response_data['response']).to match(/cool|sweet|nice|yeah|alright/i)
        when :zorp
          expect(response_data['response']).to match(/energy|vibration|dimension|cosmic/i)
        end

        puts "\n🎉 REAL END-TO-END TEST PASSED!"
      end
    end

    context 'when querying light state', skip: 'Requires real HA connection and API keys' do
      let(:message) { 'What color are the cube lights right now?' }

      it 'queries actual Home Assistant and reports real state in persona voice' do
        puts "\n🔍 Testing real query flow..."

        post '/api/v1/conversation', params: request_payload

        expect(response).to have_http_status(:ok)
        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be(true)

        response_data = response_body['data']
        conversation = Conversation.find_by(session_id: session_id)
        log = ConversationLog.find_by(session_id: session_id)
        metadata = JSON.parse(log.metadata)

        puts "   Query response: #{response_data['response']}"
        puts "   Tools used: #{metadata['sync_tools']} | #{metadata['query_tools']}"

        # Should have meaningful response about actual light state
        expect(response_data['response']).not_to eq("I understand.")
        expect(response_data['response']).to include_any_of([ 'light', 'color', 'bright', 'dim', 'off', 'on' ])

        # Query tools should execute synchronously for immediate speech
        query_tools = metadata['sync_tools'] || metadata['query_tools'] || []
        expect(query_tools).not_to be_empty, "Expected query tools to execute for light state check"

        puts "✅ Query test passed - real HA state reported in persona voice"
      end
    end
  end

  describe 'Two-Tier Architecture Validation' do
    it 'has proper structured output schema' do
      pending "TODO: Fix Schemas::NarrativeResponseSchema access - may need to properly define schema class or fix property access"
      schema = Schemas::NarrativeResponseSchema.schema
      expect(schema.name).to eq('narrative_response')

      # Verify schema structure for two-tier mode
      expect(schema.properties).to have_key('speech_text')
      expect(schema.properties).to have_key('continue_conversation')
      expect(schema.properties).to have_key('tool_intents')
    end

    it 'provides correct tools for technical LLM based on actual persona' do
      pending "TODO: Fix CubePersona.current_persona call - requires proper Home Assistant connection and mocking for test environment"
      # This tests real persona → real tool filtering
      actual_persona = CubePersona.current_persona
      tools = Tools::Registry.tool_definitions_for_two_tier_mode(actual_persona)

      expect(tools).to be_an(Array)
      expect(tools).not_to be_empty
      expect(tools.first).to respond_to(:name)

      # Should be filtered based on the actual persona from HA
      tool_names = tools.map(&:name)
      case actual_persona
      when :buddy, :jax, :zorp
        expect(tool_names).to include_any_of([ 'turn_on_light', 'set_light_color_and_brightness', 'get_light_state' ])
      end
    end
  end
end

# Helper matcher for checking if response contains any of the expected terms
RSpec::Matchers.define :include_any_of do |expected_terms|
  match do |actual|
    expected_terms.any? { |term| actual.downcase.include?(term.downcase) }
  end

  failure_message do |actual|
    "expected '#{actual}' to include any of #{expected_terms}"
  end
end
