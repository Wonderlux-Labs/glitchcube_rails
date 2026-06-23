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

    context 'when LLM returns no tool calls' do
      before do
        llm_response = instance_double(
          OpenRouter::Response,
          tool_calls: [],
          has_tool_calls?: false,
          content: "Done.",
          model: "google/gemini-3.1-flash-lite",
          usage: {}
        )
        allow(LlmService).to receive(:call_with_tools).and_return(llm_response)
      end

      it 'returns a natural language string response' do
        result = service.execute_intent(intent, context)

        expect(result).to be_a(String)
      end
    end

    context 'when LLM returns sync tool calls' do
      let(:intent) { 'What color are the lights?' }

      before do
        tool_call = instance_double(OpenRouter::ToolCall, name: "get_light_state", arguments: { "entity_id" => "light.cube_inner" }, id: "tc1")
        llm_response = instance_double(
          OpenRouter::Response,
          tool_calls: [tool_call],
          has_tool_calls?: true,
          content: nil,
          model: "google/gemini-3.1-flash-lite",
          usage: {}
        )
        allow(LlmService).to receive(:call_with_tools).and_return(llm_response)

        executor = instance_double(ToolExecutor)
        allow(ToolExecutor).to receive(:new).and_return(executor)
        allow(executor).to receive(:categorize_tool_calls).and_return({
          sync_tools: [tool_call],
          async_tools: []
        })
        allow(executor).to receive(:execute_sync).and_return({
          "get_light_state" => { success: true, message: "Light is blue" }
        })
      end

      it 'executes sync tools and returns a natural language response' do
        result = service.execute_intent(intent, context)

        expect(result).to be_a(String)
        expect(result).to include("completed")
      end
    end

    context 'when LLM returns async tool calls' do
      let(:intent) { 'Turn off all lights' }

      before do
        tool_call = instance_double(OpenRouter::ToolCall, name: "turn_off_light", arguments: { "entity_id" => "light.cube_inner" }, id: "tc2")
        llm_response = instance_double(
          OpenRouter::Response,
          tool_calls: [tool_call],
          has_tool_calls?: true,
          content: nil,
          model: "google/gemini-3.1-flash-lite",
          usage: {}
        )
        allow(LlmService).to receive(:call_with_tools).and_return(llm_response)

        executor = instance_double(ToolExecutor)
        allow(ToolExecutor).to receive(:new).and_return(executor)
        allow(executor).to receive(:categorize_tool_calls).and_return({
          sync_tools: [],
          async_tools: [tool_call]
        })
        allow(executor).to receive(:execute_async)
        allow(AsyncToolJob).to receive(:perform_later)
      end

      it 'queues async tools and returns a natural language acknowledgment' do
        result = service.execute_intent(intent, context)

        expect(result).to be_a(String)
        expect(result).to include("turning off")
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

    before do
      llm_response = instance_double(
        OpenRouter::Response,
        tool_calls: [],
        has_tool_calls?: false,
        content: "Done.",
        model: "google/gemini-3.1-flash-lite",
        usage: {}
      )
      allow(LlmService).to receive(:call_with_tools).and_return(llm_response)
    end

    it 'passes natural language intent to LLM for tool parameter translation' do
      expect(LlmService).to receive(:call_with_tools).with(
        hash_including(messages: array_including(hash_including(content: a_string_including("magenta"))))
      ).and_return(instance_double(
        OpenRouter::Response,
        tool_calls: [], has_tool_calls?: false, content: "Done.", model: "test", usage: {}
      ))

      result = service.execute_intent(intent)
      expect(result).to be_a(String)
    end
  end
end
