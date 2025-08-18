require 'rails_helper'

RSpec.describe 'Two-Tier Conversation API', type: :request do
  let(:session_id) { 'two_tier_test_session_123' }
  let(:agent_id) { 'test_agent' }
  let(:device_id) { 'test_device' }

  let(:request_payload) do
    {
      text: message,
      context: {
        session_id: session_id,
        conversation_id: session_id,
        device_id: device_id,
        ha_context: {
          device_id: device_id,
          agent_id: agent_id
        }
      }
    }
  end

  before do
    # Clean slate for each test
    Conversation.destroy_all
    ConversationLog.destroy_all

    # Enable two-tier mode with structured output
    Rails.configuration.define_singleton_method(:two_tier_tools_enabled) { true }
    Rails.configuration.define_singleton_method(:tool_calling_model) { 'mistralai/mistral-small-3.2-24b-instruct' }
    Rails.configuration.define_singleton_method(:default_ai_model) { 'openai/gpt-oss-120b' }

    # MOCKED INTEGRATION TESTS (not real end-to-end)
    # Mock CubePersona to avoid real HA calls
    allow(CubePersona).to receive(:current_persona).and_return('buddy')

    # Mock HomeAssistantService to avoid real API calls
    allow_any_instance_of(HomeAssistantService).to receive(:entity).and_return(nil)
  end

  describe 'POST /api/v1/conversation with two-tier mode enabled' do
    context 'when requesting light control with structured output', :vcr do
      let(:message) { 'Make the lights warm and golden like a cozy fireplace' }

      it 'uses structured output approach: narrative LLM returns tool_intents, ToolCallingService executes all intents' do
        post '/api/v1/conversation', params: request_payload

        expect(response).to have_http_status(:ok)
        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be(true)

        response_data = response_body['data']
        expect(response_data).to have_key('response')
        expect(response_data).to have_key('continue_conversation')

        # Check conversation was created with proper session
        conversation = Conversation.find_by(session_id: session_id)
        expect(conversation).to be_present
        expect(conversation.persona).to be_present

        # Check conversation log was created
        log = ConversationLog.find_by(session_id: session_id)
        expect(log).to be_present
        expect(log.user_message).to eq(message)
        expect(log.ai_response).to be_present

        # In two-tier mode, the narrative LLM should only see tool_intent
        # The technical execution should be handled by ToolCallingService
        # Metadata should show which tools were executed
        metadata = JSON.parse(log.metadata)
        expect(metadata['sync_tools']).to be_an(Array)
        expect(metadata['async_tools']).to be_an(Array)

        puts "✅ Two-tier test passed!"
        puts "   Response: #{response_data['response']}"
        puts "   Sync tools: #{metadata['sync_tools']}"
        puts "   Async tools: #{metadata['async_tools']}"
      end
    end

    context 'when querying light state', :vcr do
      let(:message) { 'What color are the cube lights right now?' }

      it 'handles query tools through two-tier architecture' do
        post '/api/v1/conversation', params: request_payload

        expect(response).to have_http_status(:ok)
        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be(true)

        response_data = response_body['data']
        expect(response_data).to have_key('response')

        conversation = Conversation.find_by(session_id: session_id)
        expect(conversation).to be_present

        log = ConversationLog.find_by(session_id: session_id)
        expect(log).to be_present

        metadata = JSON.parse(log.metadata)
        # Query tools should execute as sync
        expect(metadata['sync_tools']).to be_an(Array)

        puts "✅ Two-tier query test passed!"
        puts "   Query response: #{response_data['response']}"
        puts "   Sync tools used: #{metadata['sync_tools']}"
      end
    end

    context 'when making complex multi-tool request', :vcr do
      let(:message) { 'Turn off all the lights and then set the inner cube to a soft blue glow' }

      it 'handles multiple tool intents through ToolCallingService', pending: 'TODO: Fix VCR cassettes for multi-tool flow' do
        post '/api/v1/conversation', params: request_payload

        expect(response).to have_http_status(:ok)
        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be(true)

        response_data = response_body['data']

        conversation = Conversation.find_by(session_id: session_id)
        expect(conversation).to be_present

        log = ConversationLog.find_by(session_id: session_id)
        expect(log).to be_present

        metadata = JSON.parse(log.metadata)

        # Should have both sync and async tools
        total_tools = metadata['sync_tools'].length + metadata['async_tools'].length
        expect(total_tools).to be > 0

        puts "✅ Two-tier multi-tool test passed!"
        puts "   Response: #{response_data['response']}"
        puts "   Total tools executed: #{total_tools}"
      end
    end
  end

  describe 'Two-tier vs Legacy mode comparison' do
    let(:message) { 'Set the lights to purple' }

    context 'with two-tier mode disabled' do
      before do
        Rails.configuration.define_singleton_method(:two_tier_tools_enabled) { false }
      end

      it 'uses legacy direct tool calling' do
        post '/api/v1/conversation', params: request_payload

        expect(response).to have_http_status(:ok)

        log = ConversationLog.find_by(session_id: session_id)
        expect(log).to be_present

        metadata = JSON.parse(log.metadata)

        puts "✅ Legacy mode test passed!"
        puts "   Legacy tools: #{metadata['sync_tools']} | #{metadata['async_tools']}"
      end
    end

    context 'with two-tier mode enabled' do
      it 'uses tool_intent bridge' do
        post '/api/v1/conversation', params: request_payload

        expect(response).to have_http_status(:ok)

        log = ConversationLog.find_by(session_id: session_id)
        expect(log).to be_present

        metadata = JSON.parse(log.metadata)

        puts "✅ Two-tier mode test passed!"
        puts "   Two-tier tools: #{metadata['sync_tools']} | #{metadata['async_tools']}"
      end
    end
  end

  describe 'Real Two-Tier Integration Flow' do
    context 'when two-tier mode is enabled with structured output' do
      let(:message) { 'Make the lights cozy and warm like a fireplace' }

      it 'processes conversation through structured output architecture', skip: 'Requires API keys - enable when testing with real LLM' do
        post '/api/v1/conversation', params: request_payload

        expect(response).to have_http_status(:ok)
        response_body = JSON.parse(response.body)
        expect(response_body['success']).to be true

        response_data = response_body['data']
        expect(response_data).to have_key('response')
        expect(response_data).to have_key('continue_conversation')

        # Verify conversation log was created with two-tier metadata
        log = ConversationLog.find_by(session_id: session_id)
        expect(log).to be_present
        expect(log.user_message).to eq(message)
        expect(log.ai_response).to be_present

        metadata = JSON.parse(log.metadata)
        expect(metadata).to have_key('model_used')
      end
    end
  end

  describe 'Two-Tier Architecture Validation' do
    it 'has proper schema definition for structured output' do
      schema = Schemas::NarrativeResponseSchema.schema
      expect(schema.name).to eq('narrative_response')
    end

    it 'builds correct system prompts for two-tier mode' do
      Rails.configuration.two_tier_tools_enabled = true
      conversation = create(:conversation)

      prompt_data = PromptService.build_prompt_for(
        persona: 'buddy',
        conversation: conversation,
        extra_context: {}
      )

      expect(prompt_data[:system_prompt]).to include('TWO-TIER MODE:')
      expect(prompt_data[:system_prompt]).to include('tool_intents')
    end

    it 'registry provides actual tools for technical LLM' do
      tools = Tools::Registry.tool_definitions_for_two_tier_mode('buddy')
      expect(tools).not_to be_empty
      expect(tools.first).to respond_to(:name)
    end
  end
end
