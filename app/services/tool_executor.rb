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
      tool_name = tool_call.respond_to?(:name) ? tool_call.name : tool_call['name']
      arguments = tool_call.respond_to?(:arguments) ? tool_call.arguments : tool_call['arguments']
      
      # Only execute if it's a sync tool
      tool_class = Tools::Registry.get_tool(tool_name)
      next unless tool_class&.tool_type == :sync
      
      Rails.logger.info "Executing sync tool: #{tool_name} with args: #{arguments}"
      
      begin
        result = Tools::Registry.execute_tool(tool_name, **arguments.symbolize_keys)
        sync_results[tool_name] = result
        Rails.logger.info "Sync tool #{tool_name} completed: #{result[:success] ? 'success' : 'failed'}"
      rescue StandardError => e
        Rails.logger.error "Sync tool #{tool_name} failed: #{e.message}"
        sync_results[tool_name] = {
          success: false,
          error: e.message,
          tool: tool_name
        }
      end
    end
    
    sync_results
  end
  
  # Execute asynchronous tools in background (for actions after response)
  def execute_async(tool_calls, session_id: nil, conversation_id: nil)
    return unless tool_calls&.any?
    
    tool_calls.each do |tool_call|
      tool_name = tool_call.respond_to?(:name) ? tool_call.name : tool_call['name']
      arguments = tool_call.respond_to?(:arguments) ? tool_call.arguments : tool_call['arguments']
      
      # Only execute if it's an async tool
      tool_class = Tools::Registry.get_tool(tool_name)
      next unless tool_class&.tool_type == :async
      
      # Queue for background execution
      AsyncToolJob.perform_later(
        tool_name,
        arguments,
        session_id,
        conversation_id
      )
    end
  end
  
  # Execute a single tool (used by background jobs)
  def execute_single_async(tool_name, arguments)
    tool_class = Tools::Registry.get_tool(tool_name)
    
    unless tool_class
      return {
        success: false,
        error: "Tool '#{tool_name}' not found",
        tool: tool_name
      }
    end
    
    Rails.logger.info "Executing async tool: #{tool_name} with args: #{arguments}"
    
    begin
      result = Tools::Registry.execute_tool(tool_name, **arguments.symbolize_keys)
      Rails.logger.info "Async tool #{tool_name} completed: #{result[:success] ? 'success' : 'failed'}"
      result
    rescue StandardError => e
      Rails.logger.error "Async tool #{tool_name} failed: #{e.message}"
      {
        success: false,
        error: e.message,
        tool: tool_name
      }
    end
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
      tool_name = tool_call.respond_to?(:name) ? tool_call.name : tool_call['name']
      tool_class = Tools::Registry.get_tool(tool_name)
      
      next unless tool_class
      
      case tool_class.tool_type
      when :sync
        sync_tools << tool_call
      when :async
        async_tools << tool_call
      when :agent
        agent_tools << tool_call
      end
    end
    
    {
      sync_tools: sync_tools,
      async_tools: async_tools,
      agent_tools: agent_tools
    }
  end
end