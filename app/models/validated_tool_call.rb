# frozen_string_literal: true

# Wrapper around OpenRouter::ToolCall that adds validation capabilities
# This bridges the gap between OpenRouter's basic ToolCall and our needs for:
# - Parameter validation with helpful error messages
# - Integration with tool definitions' validation blocks
# - Enhanced error reporting for better UX
class ValidatedToolCall
  # Delegate core OpenRouter::ToolCall functionality
  delegate :id, :name, :arguments, :to_result_message, :to_h, :to_json, to: :@tool_call

  attr_reader :tool_call, :tool_definition

  def initialize(tool_call, tool_definition = nil)
    unless tool_call.is_a?(OpenRouter::ToolCall)
      raise ArgumentError, "Expected OpenRouter::ToolCall, got #{tool_call.class}"
    end

    @tool_call = tool_call
    @tool_definition = tool_definition
    @validation_errors = nil # Cache validation results
  end

  # Check if the tool call is valid according to its definition
  def valid?
    validation_errors.empty?
  end

  # Get detailed validation error messages
  def validation_errors
    return @validation_errors if @validation_errors

    @validation_errors = []

    # If no tool definition provided, we can only do basic checks
    if @tool_definition.nil?
      Rails.logger.warn "No tool definition provided for validation of #{name}"
      return @validation_errors
    end

    # Run custom validation blocks from the tool definition
    run_custom_validations

    @validation_errors
  end

  # Reset validation state (useful for testing)
  def reset_validation!
    @validation_errors = nil
  end

  # Get function name (alias for consistency with OpenRouter)
  def function_name
    @tool_call.function_name
  end

  # Create a ValidatedToolCall from tool call data
  def self.from_tool_call_data(tool_call_data, tool_definition = nil)
    tool_call = OpenRouter::ToolCall.new(tool_call_data)
    new(tool_call, tool_definition)
  end

  # Check if this tool call represents the same call as another
  def same_call_as?(other)
    return false unless other.is_a?(ValidatedToolCall)

    id == other.id && name == other.name && arguments == other.arguments
  end

  private

  def run_custom_validations
    return unless @tool_definition.respond_to?(:validation_blocks)

    @tool_definition.validation_blocks.each do |validation_block|
      begin
        # Pass arguments and error collection array to validation block
        validation_result = validation_block.call(arguments, @validation_errors)

        # If validation block returns an array, merge it with our errors
        if validation_result.is_a?(Array)
          @validation_errors.concat(validation_result)
        end
      rescue StandardError => e
        Rails.logger.error "Validation block failed for #{name}: #{e.message}"
        @validation_errors << "Internal validation error: #{e.message}"
      end
    end
  end
end
