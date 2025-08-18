# app/jobs/async_tool_job.rb
require "mission_control/jobs" if defined?(Rails)

class AsyncToolJob < ApplicationJob
  queue_as :default

  def perform(validated_tool_call_or_legacy_tool_name, legacy_arguments_or_session_id = nil, session_id = nil, conversation_id = nil)
    # Handle both ValidatedToolCall objects and legacy parameter format
    if validated_tool_call_or_legacy_tool_name.is_a?(ValidatedToolCall)
      validated_tool_call = validated_tool_call_or_legacy_tool_name
      session_id = legacy_arguments_or_session_id # session_id is second parameter
      tool_name = validated_tool_call.name

      Rails.logger.info "🔧 AsyncToolJob starting with ValidatedToolCall: #{tool_name} for session: #{session_id}"
    else
      # Legacy format: tool_name, tool_arguments, session_id, conversation_id
      tool_name = validated_tool_call_or_legacy_tool_name
      tool_arguments = legacy_arguments_or_session_id

      Rails.logger.info "🔧 AsyncToolJob starting (legacy): #{tool_name} for session: #{session_id}"
      Rails.logger.info "📝 Arguments received: #{tool_arguments.inspect}"

      # Clean up ActiveJob's serialization artifacts
      cleaned_arguments = clean_activejob_keys(tool_arguments)
      Rails.logger.info "🧹 Cleaned arguments: #{cleaned_arguments.inspect}"

      # Create ValidatedToolCall from legacy parameters
      validated_tool_call = create_validated_tool_call_from_legacy(tool_name, cleaned_arguments)
    end

    # Execute the tool with validation and timing
    executor = ToolExecutor.new
    Rails.logger.info "⚙️ Calling executor.execute_single_async with ValidatedToolCall"
    result = executor.execute_single_async(validated_tool_call)

    # Log the result
    Rails.logger.info "✅ AsyncToolJob result: #{result.inspect}"
    if result[:success]
      Rails.logger.info "🎉 Async tool #{validated_tool_call.name} completed successfully"
    else
      Rails.logger.error "❌ Async tool #{validated_tool_call.name} failed: #{result[:error]}"
    end

    # Store result if we have a way to track it
    if session_id
      store_tool_result(validated_tool_call.name, result, session_id, conversation_id)
    end

    # Handle any follow-up actions based on result
    handle_tool_result(validated_tool_call.name, result, session_id, conversation_id)

    result
  rescue StandardError => e
    tool_name = validated_tool_call_or_legacy_tool_name.is_a?(ValidatedToolCall) ?
      validated_tool_call_or_legacy_tool_name.name : validated_tool_call_or_legacy_tool_name

    Rails.logger.error "AsyncToolJob failed for #{tool_name}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # Record the failure in metrics
    ToolMetrics.record(tool_name: tool_name, duration_ms: 0, success: false)

    error_result = {
      success: false,
      error: "Job execution failed: #{e.message}",
      tool: tool_name
    }

    store_tool_result(tool_name, error_result, session_id, conversation_id) if session_id

    error_result
  end

  private

  # Clean ActiveJob serialization artifacts
  def clean_activejob_keys(data)
    case data
    when Hash
      data.reject { |k, v| k == "_aj_symbol_keys" }.transform_values { |v| clean_activejob_keys(v) }
    when Array
      data.map { |item| clean_activejob_keys(item) }
    else
      data
    end
  end

  # Create ValidatedToolCall from legacy tool_name + arguments
  def create_validated_tool_call_from_legacy(tool_name, arguments)
    tool_call_data = {
      "id" => "async_#{SecureRandom.uuid}",
      "type" => "function",
      "function" => {
        "name" => tool_name,
        "arguments" => arguments.to_json
      }
    }

    tool_class = Tools::Registry.get_tool(tool_name)
    ValidatedToolCall.from_tool_call_data(tool_call_data, tool_class)
  end

  def store_tool_result(tool_name, result, session_id, conversation_id)
    Rails.logger.info "Tool result for #{session_id}: #{tool_name} - #{result[:success] ? 'success' : 'failed'}"

    # Store as a system message in ConversationLog for context
    ConversationLog.create!(
      session_id: session_id,
      user_message: "[SYSTEM] Async tool completed: #{tool_name}",
      ai_response: "[SYSTEM] #{format_tool_result(result)}",
      tool_results: { tool_name => result }.to_json,
      metadata: {
        message_type: "async_tool_result",
        original_conversation_id: conversation_id,
        tool_name: tool_name,
        executed_at: Time.current.iso8601
      }.to_json
    )
  rescue StandardError => e
    Rails.logger.error "Failed to store tool result: #{e.message}"
  end

  def format_tool_result(result)
    if result[:success]
      "✅ Completed: #{result[:message] || 'Success'}"
    else
      "❌ Failed: #{result[:error] || 'Unknown error'}"
    end
  end

  def handle_tool_result(tool_name, result, session_id, conversation_id)
    # Handle specific tool results that might trigger follow-up actions
    case tool_name
    when "turn_on_light", "turn_off_light", "set_light_color_and_brightness", "set_light_effect"
      # Light control tools - could trigger status updates or notifications
      handle_light_control_result(result, session_id)
    when "call_hass_service"
      # General service calls - could have various follow-up actions
      handle_service_call_result(result, session_id)
    end
  end

  def handle_light_control_result(result, session_id)
    # Could trigger:
    # - Status update broadcasts
    # - Confirmation notifications
    # - Integration with other systems
    Rails.logger.debug "Light control completed for session #{session_id}: #{result[:success]}"
  end

  def handle_service_call_result(result, session_id)
    # Could trigger different actions based on the service called
    Rails.logger.debug "Service call completed for session #{session_id}: #{result[:success]}"
  end
end
