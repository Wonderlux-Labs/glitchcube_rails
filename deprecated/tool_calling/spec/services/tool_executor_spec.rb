# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ToolExecutor do
  let(:executor) { ToolExecutor.new }

  before do
    ToolMetrics.clear_all_metrics!
  end

  describe '#execute_sync' do
    let(:valid_tool_call) do
      tool_call_data = {
        "id" => "call_123",
        "type" => "function",
        "function" => {
          "name" => "get_light_state",
          "arguments" => '{"entity_id": "light.cube_inner"}'
        }
      }
      OpenRouter::ToolCall.new(tool_call_data)
    end

    it 'converts tool calls to ValidatedToolCall objects' do
      # Mock the tool registry
      allow(Tools::Registry).to receive(:get_tool).and_return(
        double(tool_type: :sync, validation_blocks: [])
      )
      allow(Tools::Registry).to receive(:execute_tool).and_return(
        { success: true, message: "Light is on" }
      )

      # Execute
      results = executor.execute_sync([ valid_tool_call ])

      # Should have results
      expect(results).to have_key('get_light_state')
      expect(results['get_light_state'][:success]).to be true
    end

    it 'records timing metrics for successful execution' do
      mock_tool = double('MockTool',
        tool_type: :sync,
        validation_blocks: []
      )

      allow(Tools::Registry).to receive(:get_tool).and_return(mock_tool)
      allow(Tools::Registry).to receive(:execute_tool).and_return(
        { success: true, message: "Success" }
      )

      result = executor.execute_sync([ valid_tool_call ])

      # Check that metrics were recorded
      stats = ToolMetrics.stats_for('get_light_state')
      expect(stats[:count]).to eq(1)
      expect(stats[:p95]).to be > 0 # Should have some timing
    end

    it 'handles validation failures' do
      # Mock a tool that will fail validation
      failing_validation = proc { |params, errors| errors << "Invalid entity" }
      tool_def = double(validation_blocks: [ failing_validation ], tool_type: :sync)

      allow(Tools::Registry).to receive(:get_tool).and_return(tool_def)

      results = executor.execute_sync([ valid_tool_call ])

      expect(results['get_light_state'][:success]).to be false
      expect(results['get_light_state'][:error]).to eq("Validation failed")
      expect(results['get_light_state'][:details]).to include("Invalid entity")
    end

    it 'skips non-sync tools' do
      allow(Tools::Registry).to receive(:get_tool).and_return(
        double(tool_type: :async, validation_blocks: []) # This is async, should be skipped
      )

      results = executor.execute_sync([ valid_tool_call ])

      expect(results).to be_empty
    end

    it 'handles execution errors gracefully' do
      allow(Tools::Registry).to receive(:get_tool).and_return(
        double(tool_type: :sync, validation_blocks: [])
      )
      allow(Tools::Registry).to receive(:execute_tool).and_raise(
        StandardError, "Tool execution failed"
      )

      results = executor.execute_sync([ valid_tool_call ])

      expect(results['get_light_state'][:success]).to be false
      expect(results['get_light_state'][:error]).to eq("Tool execution failed")
    end
  end

  describe '#execute_async' do
    let(:async_tool_call) do
      tool_call_data = {
        "id" => "call_async",
        "type" => "function",
        "function" => {
          "name" => "set_light_state",
          "arguments" => '{"entity_id": "light.cube_inner", "state": "on"}'
        }
      }
      OpenRouter::ToolCall.new(tool_call_data)
    end

    it 'queues async tools for background execution' do
      allow(Tools::Registry).to receive(:get_tool).and_return(
        double(tool_type: :async, validation_blocks: [])
      )

      # Mock AsyncToolJob with new signature (tool_name, arguments, session_id, conversation_id)
      expect(AsyncToolJob).to receive(:perform_later) do |tool_name, arguments, session_id, conversation_id|
        expect(tool_name).to eq('set_light_state')
        expect(arguments).to eq({ 'entity_id' => 'light.cube_inner', 'state' => 'on' })
        expect(session_id).to eq('test_session')
      end

      executor.execute_async([ async_tool_call ], session_id: 'test_session')
    end

    it 'skips invalid tools and records metrics' do
      failing_validation = proc { |params, errors| errors << "Always fails" }
      tool_def = double(validation_blocks: [ failing_validation ], tool_type: :async)

      allow(Tools::Registry).to receive(:get_tool).and_return(tool_def)

      # Should not queue the job
      expect(AsyncToolJob).not_to receive(:perform_later)

      executor.execute_async([ async_tool_call ])

      # Should record validation failure
      stats = ToolMetrics.stats_for('set_light_state')
      expect(stats[:count]).to eq(1) # Validation failure recorded
    end
  end

  describe '#execute_single_async' do
    context 'with ValidatedToolCall object' do
      let(:validated_tool_call) do
        tool_call_data = {
          "id" => "call_single",
          "type" => "function",
          "function" => {
            "name" => "test_tool",
            "arguments" => '{}'
          }
        }
        openrouter_call = OpenRouter::ToolCall.new(tool_call_data)
        ValidatedToolCall.new(openrouter_call)
      end

      it 'executes ValidatedToolCall with timing' do
        allow(Tools::Registry).to receive(:execute_tool).and_return(
          { success: true, message: "Executed" }
        )

        result = executor.execute_single_async(validated_tool_call)

        expect(result[:success]).to be true

        # Check metrics were recorded
        stats = ToolMetrics.stats_for('test_tool')
        expect(stats[:count]).to eq(1)
      end
    end

    context 'with legacy parameters' do
      it 'handles legacy tool_name + arguments format' do
        allow(Tools::Registry).to receive(:get_tool).and_return(
          double(validation_blocks: [])
        )
        allow(Tools::Registry).to receive(:execute_tool).and_return(
          { success: true, message: "Legacy execution" }
        )

        result = executor.execute_single_async('legacy_tool', { param: 'value' })

        expect(result[:success]).to be true

        # Check metrics were recorded
        stats = ToolMetrics.stats_for('legacy_tool')
        expect(stats[:count]).to eq(1)
      end

      it 'handles tool not found errors' do
        allow(Tools::Registry).to receive(:get_tool).and_return(nil)

        result = executor.execute_single_async('nonexistent_tool', {})

        expect(result[:success]).to be false
        expect(result[:error]).to include("not found")

        # Should record failure
        stats = ToolMetrics.stats_for('nonexistent_tool')
        expect(stats[:count]).to eq(1)
      end
    end
  end

  describe '#categorize_tool_calls' do
    let(:sync_call) do
      OpenRouter::ToolCall.new({
        "id" => "sync",
        "type" => "function",
        "function" => { "name" => "sync_tool", "arguments" => '{}' }
      })
    end

    let(:async_call) do
      OpenRouter::ToolCall.new({
        "id" => "async",
        "type" => "function",
        "function" => { "name" => "async_tool", "arguments" => '{}' }
      })
    end

    it 'categorizes tools by type' do
      allow(Tools::Registry).to receive(:get_tool) do |name|
        case name
        when 'sync_tool'
          double(tool_type: :sync)
        when 'async_tool'
          double(tool_type: :async)
        end
      end

      result = executor.categorize_tool_calls([ sync_call, async_call ])

      expect(result[:sync_tools].size).to eq(1)
      expect(result[:async_tools].size).to eq(1)
      expect(result[:agent_tools]).to be_empty

      # Should return ValidatedToolCall objects
      expect(result[:sync_tools].first).to be_a(ValidatedToolCall)
      expect(result[:async_tools].first).to be_a(ValidatedToolCall)
    end
  end
end
