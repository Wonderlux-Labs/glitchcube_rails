# app/services/tool_calling_service.rb
# 
# Tool-Calling LLM Service - Technical tier of two-tier architecture
# Receives natural language intent from narrative LLM and translates to precise tool calls
class ToolCallingService
  def initialize(session_id: nil, conversation_id: nil)
    @session_id = session_id
    @conversation_id = conversation_id
  end

  # Execute tool intent from narrative LLM
  # @param intent [String] Natural language description of what to do
  # @param context [Hash] Additional context from conversation
  # @return [Hash] Success/failure with natural language description
  def execute_intent(intent, context = {})
    Rails.logger.info "🔧 ToolCallingService executing intent: #{intent}"
    
    # Call LLM to translate intent to tool calls
    tool_calls_response = call_tool_calling_llm(intent, context)
    
    return error_response("Failed to generate tool calls") unless tool_calls_response
    
    # Execute the tool calls
    results = execute_tool_calls(tool_calls_response.tool_calls)
    
    # Return natural language summary
    format_results_for_narrative(results, intent)
  end

  private

  def call_tool_calling_llm(intent, context)
    prompt = build_tool_calling_prompt(intent, context)
    model = determine_tool_calling_model
    
    # Get persona from context, default to 'jax'
    persona = context&.dig(:persona) || 'jax'
    
    Rails.logger.info "🚀 Calling tool-calling LLM (#{model}) with persona-specific tools for #{persona}"
    
    LlmService.call_with_tools(
      messages: prompt,
      tools: Tools::Registry.tool_definitions_for_two_tier_mode(persona), # Only persona-specific tools
      model: model,
      temperature: 0.1 # Low temperature for precise technical execution
    )
  end

  def determine_tool_calling_model
    # Use configured tool-calling model, default_tools_model, or fall back to default AI model
    Rails.configuration.try(:tool_calling_model) ||
    Rails.configuration.try(:default_tools_model) ||
    Rails.configuration.default_ai_model
  end

  def build_tool_calling_prompt(intent, context)
    [
      {
        role: "system",
        content: <<~SYSTEM
          You are a technical tool execution service. Your job is to translate natural language intent into precise tool calls.
          
          USER INTENT: #{intent}
          
          CONTEXT: #{context.to_json}
          
          IMPORTANT RULES:
          - Use EXACT parameter names from tool definitions
          - For colors: use rgb_color parameter with [R, G, B] values (0-255)
          - For brightness: use brightness_percent parameter (0-100)
          - Common color translations:
            * red: [255, 0, 0]
            * green: [0, 255, 0] 
            * blue: [0, 0, 255]
            * magenta: [255, 0, 255]
            * yellow: [255, 255, 0]
            * white: [255, 255, 255]
            * orange: [255, 165, 0]
            * purple: [128, 0, 128]
          
          Make the precise tool calls needed to fulfill the intent.
        SYSTEM
      },
      {
        role: "user", 
        content: "Execute this intent: #{intent}"
      }
    ]
  end

  def execute_tool_calls(tool_calls)
    return {} unless tool_calls&.any?
    
    results = {}
    tool_executor = ToolExecutor.new
    categorized = tool_executor.categorize_tool_calls(tool_calls)
    
    # Execute sync tools immediately
    if categorized[:sync_tools].any?
      sync_results = tool_executor.execute_sync(categorized[:sync_tools])
      results.merge!(sync_results)
    end
    
    # Queue async tools
    if categorized[:async_tools].any?
      tool_executor.execute_async(categorized[:async_tools], 
                                 session_id: @session_id, 
                                 conversation_id: @conversation_id)
      
      # Note async tools for result formatting
      categorized[:async_tools].each do |tool_call|
        tool_name = tool_call.respond_to?(:name) ? tool_call.name : tool_call['name']
        results[tool_name] = { success: true, message: "Queued for execution", async: true }
      end
    end
    
    results
  end

  def format_results_for_narrative(results, original_intent)
    return "I'll handle that." if results.empty?
    
    successes = []
    failures = []
    async_actions = []
    
    results.each do |tool_name, result|
      if result[:async]
        async_actions << humanize_tool_name(tool_name)
      elsif result[:success]
        successes << humanize_tool_name(tool_name)
      else
        failures << "#{humanize_tool_name(tool_name)} (#{result[:error]})"
      end
    end
    
    response_parts = []
    
    if async_actions.any?
      response_parts << "I'm #{async_actions.join(' and ')}"
    end
    
    if successes.any?
      response_parts << "#{successes.join(' and ')} completed"
    end
    
    if failures.any?
      response_parts << "but #{failures.join(' and ')} failed"
    end
    
    response_parts.any? ? response_parts.join(', ') : "Working on it."
  end

  def humanize_tool_name(tool_name)
    case tool_name
    when "turn_on_light"
      "turning on the lights"
    when "turn_off_light"
      "turning off the lights"
    when "set_light_color_and_brightness"
      "adjusting the lighting"
    when "set_light_effect"
      "setting a light effect"
    when "get_light_state"
      "checking light status"
    when "list_light_effects"
      "listing available effects"
    when "play_music"
      "playing music"
    when "display_notification"
      "displaying a message"
    when "control_effects"
      "controlling environmental effects"
    when "mode_control"
      "changing operational mode"
    when "make_announcement"
      "making an announcement"
    else
      tool_name.humanize.downcase
    end
  end

  def error_response(message)
    {
      success: false,
      error: message,
      natural_response: "I'm having trouble with that right now."
    }
  end
end