# frozen_string_literal: true

class CubeData::Tools < CubeData
  class << self
    # Record tool execution
    def record_execution(tool_name, success, execution_time, parameters = {}, error_message = nil)
      write_sensor(
        sensor_id(:tools, :last_execution),
        tool_name,
        {
          tool_name: tool_name,
          success: success,
          execution_time: execution_time,
          parameters: parameters.to_json,
          error_message: error_message,
          timestamp: Time.current.iso8601
        }
      )

      # Update failure tracking if it failed
      if !success
        record_failure(tool_name, error_message)
      end

      status = success ? "SUCCESS" : "FAILED"
      Rails.logger.info "🔧 Tool execution logged: #{tool_name} - #{status}"
    end

    # Update tool execution statistics
    def update_stats(total_executions, successful_executions, failed_executions, avg_execution_time = 0)
      success_rate = total_executions > 0 ? (successful_executions.to_f / total_executions * 100).round(2) : 0

      write_sensor(
        sensor_id(:tools, :execution_stats),
        total_executions,
        {
          total_executions: total_executions,
          successful_executions: successful_executions,
          failed_executions: failed_executions,
          success_rate: success_rate,
          avg_execution_time: avg_execution_time,
          last_updated: Time.current.iso8601
        }
      )

      Rails.logger.debug "🔧 Tool stats updated: #{success_rate}% success rate"
    end

    # Record tool failure
    def record_failure(tool_name, error_message = nil, additional_info = {})
      write_sensor(
        sensor_id(:tools, :failures),
        tool_name,
        {
          tool_name: tool_name,
          error_message: error_message,
          failed_at: Time.current.iso8601,
          **additional_info
        }
      )

      Rails.logger.warn "🔧 Tool failure recorded: #{tool_name}"
    end

    # Get last tool execution
    def last_execution
      read_sensor(sensor_id(:tools, :last_execution))
    end

    # Get last executed tool name
    def last_tool_name
      execution = last_execution
      execution&.dig("state")
    end

    # Check if last execution was successful
    def last_execution_successful?
      execution = last_execution
      execution&.dig("attributes", "success") == true
    end

    # Get last execution time
    def last_execution_time
      execution = last_execution
      timestamp = execution&.dig("attributes", "timestamp")
      timestamp ? Time.parse(timestamp) : nil
    rescue
      nil
    end

    # Get execution statistics
    def stats
      read_sensor(sensor_id(:tools, :execution_stats))
    end

    # Get total executions
    def total_executions
      stats_data = stats
      stats_data&.dig("state")&.to_i || 0
    end

    # Get success rate
    def success_rate
      stats_data = stats
      stats_data&.dig("attributes", "success_rate")&.to_f || 0.0
    end

    # Get average execution time
    def avg_execution_time
      stats_data = stats
      stats_data&.dig("attributes", "avg_execution_time")&.to_f || 0.0
    end

    # Get last failure info
    def last_failure
      read_sensor(sensor_id(:tools, :failures))
    end

    # Get last failed tool
    def last_failed_tool
      failure = last_failure
      failure&.dig("state")
    end

    # Get last failure message
    def last_failure_message
      failure = last_failure
      failure&.dig("attributes", "error_message")
    end

    # Check if there were recent failures
    def recent_failures?(within = 10.minutes)
      failure = last_failure
      timestamp = failure&.dig("attributes", "failed_at")
      return false unless timestamp

      Time.parse(timestamp) > within.ago
    rescue
      false
    end

    # Get execution summary
    def execution_summary
      {
        last_tool: last_tool_name,
        last_success: last_execution_successful?,
        total_executions: total_executions,
        success_rate: success_rate,
        avg_time: avg_execution_time,
        recent_failures: recent_failures?
      }
    end
  end
end
