# app/services/tool_executor.rb
class ToolExecutor
  def initialize
    @results = {}
  end

  # Execute synchronous tools immediately (for data needed in response)
  def execute_sync(tool_calls)
    return {} if tool_calls.nil? || tool_calls.empty?

    sync_results = {}

    tool_calls.each do |tool_call|
      # Ensure we have a ValidatedToolCall object
      validated_tool_call = ensure_validated_tool_call(tool_call)

      # Only execute if it's a sync tool
      tool_class = Tools::Registry.get_tool(validated_tool_call.name)
      next unless tool_class&.tool_type == :sync

      Rails.logger.info "Executing sync tool: #{validated_tool_call.name}"

      # Validate before execution
      unless validated_tool_call.valid?
        Rails.logger.warn "⚠️ Tool validation failed: #{validated_tool_call.name}"
        sync_results[validated_tool_call.name] = {
          success: false,
          error: "Validation failed",
          details: validated_tool_call.validation_errors,
          tool: validated_tool_call.name
        }

        # Record validation failure as 0ms (immediate failure)
        ToolMetrics.record(
          tool_name: validated_tool_call.name,
          duration_ms: 0,
          success: false
        )
        next
      end

      # Execute with timing
      result = execute_with_timing(validated_tool_call)
      sync_results[validated_tool_call.name] = result
    end

    sync_results
  end

  # Execute asynchronous tools in background (for actions after response)
  def execute_async(tool_calls, session_id: nil, conversation_id: nil)
    return unless tool_calls&.any?

    tool_calls.each do |tool_call|
      # Ensure we have a ValidatedToolCall object
      validated_tool_call = ensure_validated_tool_call(tool_call)

      # Only execute if it's an async tool
      tool_class = Tools::Registry.get_tool(validated_tool_call.name)
      next unless tool_class&.tool_type == :async

      # Skip if validation fails (log but don't queue invalid tools)
      unless validated_tool_call.valid?
        Rails.logger.error "❌ Skipping async tool due to validation failure: #{validated_tool_call.name}"
        Rails.logger.error "Validation errors: #{validated_tool_call.validation_errors.join(', ')}"

        # Record validation failure
        ToolMetrics.record(
          tool_name: validated_tool_call.name,
          duration_ms: 0,
          success: false
        )
        next
      end

      # Queue for background execution with serializable data
      AsyncToolJob.perform_later(
        validated_tool_call.name,
        validated_tool_call.arguments,
        session_id,
        conversation_id
      )
    end
  end

  # Execute a single tool (used by background jobs)
  def execute_single_async(validated_tool_call_or_legacy_args, legacy_arguments = nil)
    # Handle both new ValidatedToolCall objects and legacy tool_name + arguments
    if validated_tool_call_or_legacy_args.is_a?(ValidatedToolCall)
      validated_tool_call = validated_tool_call_or_legacy_args
      Rails.logger.info "🔧 ToolExecutor.execute_single_async with ValidatedToolCall: #{validated_tool_call.name}"
    else
      # Legacy support: tool_name, arguments
      tool_name = validated_tool_call_or_legacy_args
      arguments = legacy_arguments

      Rails.logger.info "🔧 ToolExecutor.execute_single_async (legacy): #{tool_name}"
      Rails.logger.info "📝 Arguments: #{arguments.inspect}"

      # Create ValidatedToolCall from legacy parameters
      tool_class = Tools::Registry.get_tool(tool_name)
      unless tool_class
        error_result = {
          success: false,
          error: "Tool '#{tool_name}' not found",
          tool: tool_name
        }
        Rails.logger.error "❌ Tool not found: #{tool_name}"

        # Record failure
        ToolMetrics.record(tool_name: tool_name, duration_ms: 0, success: false)
        return error_result
      end

      # Create a minimal ToolCall object for validation
      tool_call_data = {
        "id" => "async_#{SecureRandom.uuid}",
        "type" => "function",
        "function" => {
          "name" => tool_name,
          "arguments" => arguments.to_json
        }
      }

      validated_tool_call = ValidatedToolCall.from_tool_call_data(tool_call_data, tool_class)
    end

    # Execute with validation and timing
    execute_with_timing(validated_tool_call)
  end

  # Get tool definitions for LLM
  def available_tool_definitions
    Tools::Registry.tool_definitions_for_llm
  end

  # Categorize tool calls by execution type
  def categorize_tool_calls(tool_calls)
    return { sync_tools: [], async_tools: [], agent_tools: [] } unless tool_calls&.any?

    sync_tools = []
    async_tools = []
    agent_tools = []

    tool_calls.each do |tool_call|
      validated_tool_call = ensure_validated_tool_call(tool_call)
      tool_class = Tools::Registry.get_tool(validated_tool_call.name)

      next unless tool_class

      case tool_class.tool_type
      when :sync
        sync_tools << validated_tool_call
      when :async
        async_tools << validated_tool_call
      when :agent
        agent_tools << validated_tool_call
      end
    end

    {
      sync_tools: sync_tools,
      async_tools: async_tools,
      agent_tools: agent_tools
    }
  end

  private

  # Ensure we have a ValidatedToolCall object
  def ensure_validated_tool_call(tool_call)
    return tool_call if tool_call.is_a?(ValidatedToolCall)

    # Handle OpenRouter::ToolCall objects
    if tool_call.is_a?(OpenRouter::ToolCall)
      tool_class = Tools::Registry.get_tool(tool_call.name)
      return ValidatedToolCall.new(tool_call, tool_class)
    end

    # Handle hash/legacy tool call data
    tool_name = tool_call.respond_to?(:name) ? tool_call.name : tool_call["name"]
    arguments = tool_call.respond_to?(:arguments) ? tool_call.arguments : tool_call["arguments"]

    tool_call_data = {
      "id" => "legacy_#{SecureRandom.uuid}",
      "type" => "function",
      "function" => {
        "name" => tool_name,
        "arguments" => arguments.is_a?(String) ? arguments : arguments.to_json
      }
    }

    tool_class = Tools::Registry.get_tool(tool_name)
    ValidatedToolCall.from_tool_call_data(tool_call_data, tool_class)
  end

  # Execute tool with timing metrics
  def execute_with_timing(validated_tool_call)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)

    # Validate before execution
    unless validated_tool_call.valid?
      duration_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_time

      # Record validation failure
      ToolMetrics.record(
        tool_name: validated_tool_call.name,
        duration_ms: duration_ms,
        success: false
      )

      Rails.logger.error "❌ Tool validation failed: #{validated_tool_call.name}"
      Rails.logger.error "Validation errors: #{validated_tool_call.validation_errors.join(', ')}"

      return {
        success: false,
        error: "Validation failed",
        details: validated_tool_call.validation_errors,
        tool: validated_tool_call.name,
        validation_time_ms: duration_ms.round(2)
      }
    end

    begin
      Rails.logger.info "🚀 Executing tool: #{validated_tool_call.name}"

      # Execute the actual tool
      result = Tools::Registry.execute_tool(
        validated_tool_call.name,
        **validated_tool_call.arguments.symbolize_keys
      )

      duration_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_time
      success = result[:success] != false # Default to true unless explicitly false

      # Record metrics
      ToolMetrics.record(
        tool_name: validated_tool_call.name,
        duration_ms: duration_ms,
        success: success,
        entity_id: validated_tool_call.arguments["entity_id"]
      )

      Rails.logger.info "✅ Tool #{validated_tool_call.name} completed in #{duration_ms.round(2)}ms"

      result

    rescue StandardError => e
      duration_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_time

      # Record failed execution
      ToolMetrics.record(
        tool_name: validated_tool_call.name,
        duration_ms: duration_ms,
        success: false
      )

      Rails.logger.error "❌ Tool execution failed: #{validated_tool_call.name} - #{e.message}"
      Rails.logger.error "🔍 Backtrace: #{e.backtrace.first(5).join("\n")}"

      {
        success: false,
        error: e.message,
        tool: validated_tool_call.name,
        execution_time_ms: duration_ms.round(2)
      }
    end
  end
end
