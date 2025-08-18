require 'rails_helper'

RSpec.describe ToolCallingService, type: :service do
  let(:session_id) { 'test_session_123' }
  let(:conversation_id) { 'conv_456' }
  let(:service) { described_class.new(session_id: session_id, conversation_id: conversation_id) }

  before do
    # Mock configuration by defining accessors
    Rails.configuration.define_singleton_method(:tool_calling_model) { 'gpt-4o-mini' }
    Rails.configuration.define_singleton_method(:default_ai_model) { 'gpt-4o' }
  end

  describe '#execute_intent' do
    let(:intent) { 'Make the lights warm and golden' }
    let(:context) { { persona: 'jax' } }

    before do
      # Mock Home Assistant service for tool execution
      allow(HomeAssistantService).to receive(:new).and_return(double)
      allow_any_instance_of(HomeAssistantService).to receive(:call_service).and_return({
        'success' => true,
        'message' => 'Service called successfully'
      })

      # Mock tool registry to return available entities
      allow(Tools::Registry).to receive(:cube_light_entities).and_return([
        'light.cube_inner',
        'light.cube_voice_ring'
      ])
    end

    context 'when LLM returns valid tool calls', :vcr do
      it 'translates intent to precise tool execution', pending: 'TODO: Setup VCR cassettes for API integration' do
        result = service.execute_intent(intent, context)

        expect(result).to include(:success, :natural_response, :tools_executed)
        expect(result[:success]).to be(true)
        expect(result[:natural_response]).to be_a(String)
        expect(result[:tools_executed]).to be_an(Array)

        puts "✅ ToolCallingService execution test passed!"
        puts "   Natural response: #{result[:natural_response]}"
        puts "   Tools executed: #{result[:tools_executed]}"
      end
    end

    context 'when handling sync tools' do
      let(:intent) { 'What color are the lights?' }

      it 'executes sync tools immediately and returns results', pending: 'TODO: Setup VCR cassettes for sync tools' do
        result = service.execute_intent(intent, context)

        expect(result).to include(:success)
        expect(result[:success]).to be(true)

        puts "✅ Sync tool execution test passed!"
        puts "   Query result: #{result[:natural_response]}"
      end
    end

    context 'when handling async tools' do
      let(:intent) { 'Turn off all lights' }

      it 'queues async tools and returns acknowledgment', pending: 'TODO: Setup VCR cassettes for async tools' do
        # Mock async job execution
        allow(AsyncToolJob).to receive(:perform_later)

        result = service.execute_intent(intent, context)

        expect(result).to include(:success)
        expect(result[:success]).to be(true)

        puts "✅ Async tool queueing test passed!"
        puts "   Async response: #{result[:natural_response]}"
      end
    end
  end

  describe '#determine_tool_calling_model' do
    context 'when tool_calling_model is configured' do
      before do
        allow(Rails.configuration).to receive(:tool_calling_model).and_return('custom-model')
      end

      it 'uses the configured model' do
        model = service.send(:determine_tool_calling_model)
        expect(model).to eq('custom-model')
      end
    end

    context 'when tool_calling_model is not configured' do
      before do
        allow(Rails.configuration).to receive(:tool_calling_model).and_return(nil)
        allow(Rails.configuration).to receive(:default_ai_model).and_return('gpt-4o')
      end

      it 'falls back to default AI model' do
        model = service.send(:determine_tool_calling_model)
        expect(model).to eq('gpt-4o')
      end
    end
  end

  describe '#format_results_for_narrative' do
    context 'with successful sync results' do
      let(:results) do
        {
          'get_light_state' => { success: true, message: 'Light is blue' }
        }
      end
      let(:intent) { 'Check light color' }

      it 'formats results into natural language' do
        response = service.send(:format_results_for_narrative, results, intent)

        expect(response).to be_a(String)
        expect(response).to include('completed')

        puts "✅ Result formatting test passed!"
        puts "   Formatted response: #{response}"
      end
    end

    context 'with async results' do
      let(:results) do
        {
          'turn_on_light' => { success: true, message: 'Queued for execution', async: true }
        }
      end
      let(:intent) { 'Turn on lights' }

      it 'acknowledges async actions' do
        response = service.send(:format_results_for_narrative, results, intent)

        expect(response).to be_a(String)
        expect(response).to include('turning on')

        puts "✅ Async formatting test passed!"
        puts "   Async response: #{response}"
      end
    end

    context 'with failed results' do
      let(:results) do
        {
          'turn_on_light' => { success: false, error: 'Entity not found' }
        }
      end
      let(:intent) { 'Turn on lights' }

      it 'reports failures naturally' do
        response = service.send(:format_results_for_narrative, results, intent)

        expect(response).to be_a(String)
        expect(response).to include('failed')

        puts "✅ Failure formatting test passed!"
        puts "   Error response: #{response}"
      end
    end
  end

  describe 'parameter translation' do
    let(:intent) { 'Set lights to magenta at 75% brightness' }

    it 'translates natural language to precise parameters', :vcr do
      pending "TODO: Fix parameter translation test - requires proper VCR cassettes and LLM API integration for natural language processing"
      result = service.execute_intent(intent)

      expect(result[:success]).to be(true)

      # The ToolCallingService should have translated:
      # - "magenta" → rgb_color: [255, 0, 255]
      # - "75% brightness" → brightness_percent: 75
      puts "✅ Parameter translation test passed!"
      puts "   Response: #{result[:natural_response]}"
    end
  end
end
