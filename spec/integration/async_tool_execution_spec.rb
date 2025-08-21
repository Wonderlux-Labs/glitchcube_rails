# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Async Tool Execution Integration", type: :integration do
  include ToolTestHelpers

  describe "end-to-end async tool execution" do
    let(:session_id) { 'test_session_async' }
    let(:conversation_id) { 'test_conversation_async' }

    before do
      # Set up ActiveJob to use test adapter for synchronous execution
      ActiveJob::Base.queue_adapter = :test

      # Clear any previous metrics
      ToolMetrics.clear_all_metrics!

      # Mock HomeAssistant service calls
      mock_entities
      mock_service_call({})
    end

    it "successfully executes async tools through the full pipeline" do
      # Create a tool call that should be executed async
      tool_call_data = {
        "id" => "async_integration_test",
        "type" => "function",
        "function" => {
          "name" => "set_light_state",
          "arguments" => JSON.generate({
            "entity_id" => "light.cube_inner",
            "state" => "on",
            "rgb_color" => "255,128,0",
            "brightness" => 75
          })
        }
      }

      openrouter_call = OpenRouter::ToolCall.new(tool_call_data)

      # Get the tool definition (this should work without mocking)
      tool_definition = Tools::Registry.get_tool('set_light_state')
      expect(tool_definition).not_to be_nil

      # Create ValidatedToolCall
      validated_call = ValidatedToolCall.new(openrouter_call, tool_definition)
      expect(validated_call).to be_valid

      # Execute through ToolExecutor.execute_async
      executor = ToolExecutor.new

      # This should not raise serialization errors
      expect {
        executor.execute_async([ validated_call ], session_id: session_id, conversation_id: conversation_id)
      }.not_to raise_error

      # Check that the job was enqueued (but not necessarily executed yet with test adapter)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.size).to eq(1)

      enqueued_job = ActiveJob::Base.queue_adapter.enqueued_jobs.first
      expect(enqueued_job[:job]).to eq(AsyncToolJob)

      # Verify the job arguments are serializable
      expect(enqueued_job[:args]).to be_an(Array)
      expect(enqueued_job[:args][0]).to eq('set_light_state') # tool_name
      expect(enqueued_job[:args][1]).to be_a(Hash) # arguments
      expect(enqueued_job[:args][2]).to eq(session_id)
      expect(enqueued_job[:args][3]).to eq(conversation_id)
    end

    it "handles job execution and result storage" do
      # Perform the job synchronously for testing
      job_result = AsyncToolJob.perform_now(
        'set_light_state',
        {
          'entity_id' => 'light.cube_inner',
          'state' => 'on',
          'rgb_color' => '255,128,0',
          'brightness' => 75
        },
        session_id,
        conversation_id
      )

      # Verify the job completed successfully
      expect(job_result).to be_a(Hash)
      expect(job_result[:success]).to be_truthy

      # Verify metrics were recorded
      stats = ToolMetrics.stats_for('set_light_state')
      expect(stats[:count]).to eq(1)
      expect(stats[:p95]).to be > 0 # Should have recorded some timing

      # Verify conversation log was created (if ConversationLog exists)
      if defined?(ConversationLog)
        log_entry = ConversationLog.where(session_id: session_id).last
        if log_entry
          expect(log_entry.user_message).to include('Async tool completed')
          expect(log_entry.metadata).to include('"message_type":"async_tool_result"')
        end
      end
    end

    it "gracefully handles tool validation failures in async execution" do
      # Test with invalid arguments that should fail validation
      job_result = AsyncToolJob.perform_now(
        'set_light_state',
        { 'entity_id' => 'light.invalid_entity' }, # Missing required parameters
        session_id,
        conversation_id
      )

      # Job should complete but tool should fail
      expect(job_result).to be_a(Hash)
      expect(job_result[:success]).to be_falsey
      expect(job_result[:error]).to be_present

      # Metrics should still be recorded for the failure
      stats = ToolMetrics.stats_for('set_light_state')
      expect(stats[:count]).to eq(1)
    end
  end
end
