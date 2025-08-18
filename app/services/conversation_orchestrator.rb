# app/services/conversation_orchestrator.rb
class ConversationOrchestrator
  def initialize(session_id:, message:, context: {})
    @session_id = session_id
    @message = message
    @context = context
  end

  def call
    Rails.logger.info "🧠 Starting conversation orchestration for: #{@message}"
    
    # Get or create conversation
    @conversation = find_or_create_conversation
    
    # Build prompt with tools for current persona (check live, don't use stored)
    current_persona = determine_persona
    
    # Add session_id to context for memory retrieval
    enhanced_context = @context.merge(session_id: @session_id)
    
    prompt_data = PromptService.build_prompt_for(
      persona: current_persona,
      conversation: @conversation,
      extra_context: enhanced_context
    )
    
    # PHASE 1: Check for previous pending tools and inject results
    previous_results = check_and_clear_pending_tools(@conversation)
    if previous_results.any?
      inject_tool_results_into_messages(prompt_data, previous_results)
    end
    
    Rails.logger.info "🎭 Using persona: #{current_persona}"
    
    # Check if two-tier mode is enabled
    if two_tier_mode_enabled?
      Rails.logger.info "🏗️ Two-tier mode enabled - using structured output"
      
      # Prepare messages for LLM
      messages = [
        { role: 'system', content: prompt_data[:system_prompt] }
      ]
      messages.concat(prompt_data[:messages]) if prompt_data[:messages].any?
      messages << { role: 'user', content: @message }
      
      # Call LLM with structured output (no tools)
      response = LlmService.call_with_structured_output(
        messages: messages,
        response_format: Schemas::NarrativeResponseSchema.schema,
        model: determine_model_for_conversation
      )
      
      sync_results = execute_tool_intents(response.structured_output)
      
      # Initialize tool_analysis for two-tier mode (needed for later processing)
      tool_analysis = { 
        sync_tools: [], 
        async_tools: [], 
        query_tools: [], 
        action_tools: [] 
      }
    else
      Rails.logger.info "🛠️ Legacy mode - using tool calling"
      Rails.logger.info "🛠️ Available tools: #{prompt_data[:tools]&.map(&:name)&.join(', ')}"
      
      # Call OpenRouter with tools enabled
      response = call_openrouter_with_tools(prompt_data)
      
      # Categorize tool calls
      tool_analysis = Tools::Registry.categorize_tool_calls(response.tool_calls || [])
      
      Rails.logger.info "🔧 Tool analysis: #{tool_analysis[:sync_tools].length} sync, #{tool_analysis[:async_tools].length} async, #{tool_analysis[:query_tools].length} query, #{tool_analysis[:action_tools].length} action"
      
      # Execute sync tools immediately
      sync_results = execute_sync_tools(tool_analysis[:sync_tools])
    end
    
    # Generate final AI response incorporating sync tool results
    ai_response = generate_ai_response(prompt_data, response, sync_results)
    
    # Queue async tools for background execution
    queue_async_tools(tool_analysis[:async_tools], ai_response[:id])
    
    # Store pending tools for next turn
    if tool_analysis[:async_tools].any?
      store_pending_tools(@conversation, tool_analysis[:async_tools])
    end
    
    # Store conversation log
    store_conversation_log(@conversation, ai_response, sync_results, tool_analysis)
    
    # Return formatted response for Home Assistant
    format_response_for_hass(ai_response, tool_analysis)
  end
  
  private
  
  def find_or_create_conversation
    # Check if existing conversation is stale (last message > 3 minutes old)
    existing_conversation = Conversation.find_by(session_id: @session_id)
    
    # LOG CONVERSATION TYPE for debugging
    if existing_conversation&.conversation_logs&.any?
      Rails.logger.info "🔄 **CONTINUING CONVERSATION** - Session: #{@session_id}, Messages: #{existing_conversation.conversation_logs.count}"
    else
      Rails.logger.info "🆕 **NEW CONVERSATION** - Session: #{@session_id}"
    end
    
    if existing_conversation&.conversation_logs&.any?
      last_message_time = existing_conversation.conversation_logs.maximum(:created_at)
      if last_message_time && last_message_time < 3.minutes.ago
        Rails.logger.info "🕒 Session #{@session_id} is stale (last message: #{last_message_time}), ending and creating memories"
        
        # End the stale conversation (memories will be created by batch job)
        if existing_conversation.active?
          existing_conversation.end!
          Rails.logger.info "🧠 Ended stale conversation: #{@session_id}"
        end
        
        # Generate new session ID with timestamp suffix
        original_id = @session_id.split('_stale_').first
        @session_id = "#{original_id}_stale_#{Time.current.to_i}"
        Rails.logger.info "🆕 New session ID: #{@session_id}"
        existing_conversation = nil
      end
    end
    
    # Find or create with the (possibly new) session_id
    Conversation.find_or_create_by(session_id: @session_id) do |conv|
      conv.started_at = Time.current
      conv.persona = determine_persona
      # Store agent_id and other metadata for persona switching logic
      conv.metadata_json = {
        agent_id: @context[:agent_id],
        device_id: @context[:device_id],
        source: @context[:source],
        original_session_id: (existing_conversation ? @session_id.split('_stale_').first : @session_id)
      }.compact
    end
  end
  
  def determine_persona
    # Single source of truth: CubePersona.current_persona
    # Allow context override for console/testing, but log it
    if @context[:persona] && @context[:persona] != CubePersona.current_persona
      Rails.logger.info "🎭 Persona override: using #{@context[:persona]} instead of #{CubePersona.current_persona}"
      @context[:persona]
    else
      CubePersona.current_persona
    end
  end
  
  def call_openrouter_with_tools(prompt_data)
    # Prepare messages for OpenRouter
    messages = [
      { role: 'system', content: prompt_data[:system_prompt] }
    ]
    
    # Add conversation history
    messages.concat(prompt_data[:messages]) if prompt_data[:messages].any?
    
    # Add current user message
    messages << { role: 'user', content: @message }
    
    # LOG FULL PROMPT for debugging
    Rails.logger.info "🎯 FULL PROMPT TO LLM:"
    Rails.logger.info "📝 System: #{messages.find { |m| m[:role] == 'system' }&.dig(:content)&.truncate(500)}"
    Rails.logger.info "💬 Messages: #{messages.select { |m| m[:role] != 'system' }.map { |m| "#{m[:role]}: #{m[:content].truncate(100)}" }.join(' | ')}"
    Rails.logger.info "🛠️ Tools: #{prompt_data[:tools]&.map(&:name)&.join(', ')}"
    
    # Call LLM with tools using our unified service
    LlmService.call_with_tools(
      messages: messages,
      tools: prompt_data[:tools],
      model: determine_model_for_conversation
    )
  end
  
  def determine_model_for_conversation
    # Use model from context, persona preference, or default
    @context[:model] ||
    get_persona_preferred_model ||
    Rails.configuration.default_ai_model
  end

  def two_tier_mode_enabled?
    Rails.configuration.try(:two_tier_tools_enabled) || false
  end


  def execute_tool_intents(structured_output)
    return {} unless structured_output&.dig("tool_intents")&.any?
    
    tool_intents = structured_output["tool_intents"]
    
    Rails.logger.info "🎭 Processing #{tool_intents.length} tool intents from narrative LLM"
    
    # Log all intents
    tool_intents.each_with_index do |intent_data, index|
      Rails.logger.info "🔧 Intent #{index + 1}: #{intent_data['tool']} - #{intent_data['intent']}"
    end
    
    begin
      # Make ONE call to ToolCallingService with all intents
      tool_calling_service = ToolCallingService.new(
        session_id: @session_id,
        conversation_id: @conversation&.id
      )
      
      # Pass all intents as a combined instruction
      combined_intent = tool_intents.map { |i| "#{i['tool']}: #{i['intent']}" }.join("; ")
      
      result = tool_calling_service.execute_intent(combined_intent, { persona: CubePersona.current_persona.to_s })
      
      Rails.logger.info "✅ All intents processed: #{result[:success] ? 'success' : 'failed'}"
      
      return { "all_intents" => result }
      
    rescue StandardError => e
      Rails.logger.error "❌ Tool intents execution failed: #{e.message}"
      return { "all_intents" => { success: false, error: e.message } }
    end
  end
  
  def get_persona_preferred_model
    # TODO: Different personas might prefer different models
    # For now, all use default
    # Future: return persona-specific models for different capabilities
    nil
  end
  
  
  def execute_sync_tools(sync_tools)
    return {} if sync_tools.blank?
    
    results = {}
    sync_tools.each do |tool_call|
      tool_name = tool_call.respond_to?(:name) ? tool_call.name : tool_call['name']
      arguments = tool_call.respond_to?(:arguments) ? tool_call.arguments : tool_call['arguments']
      
      begin
        # For tool_intent, pass session and conversation context
        if tool_name == "tool_intent"
          arguments_with_context = arguments.symbolize_keys.merge(
            session_id: @session_id,
            conversation_id: @conversation&.id,
            persona: current_persona
          )
          result = Tools::Registry.execute_tool(tool_name, **arguments_with_context)
        else
          result = Tools::Registry.execute_tool(tool_name, **arguments.symbolize_keys)
        end
        results[tool_name] = result
      rescue StandardError => e
        results[tool_name] = { success: false, error: e.message, tool: tool_name }
      end
    end
    
    results
  end
  
  def generate_ai_response(prompt_data, openrouter_response, sync_results)
    response_id = SecureRandom.uuid
    
    # Extract narrative elements from response - handle both structured and legacy modes
    if openrouter_response.structured_output
      # Two-tier mode: use structured output directly
      structured_data = openrouter_response.structured_output
      speech_text = structured_data["speech_text"]
      continue_conversation = structured_data["continue_conversation"] || false
      
      # Extract narrative metadata if available  
      narrative = {
        continue_conversation: continue_conversation,
        inner_thoughts: structured_data["inner_thoughts"],
        current_mood: structured_data["current_mood"], 
        pressing_questions: structured_data["pressing_questions"],
        speech_text: speech_text
      }
    else
      # Legacy mode: extract from content markers
      content = openrouter_response.content || ""
      narrative = extract_narrative_elements(content)
      speech_text = narrative[:speech_text]
    end
    
    # CRITICAL FIX: Handle empty speech ONLY when LLM returns no content AND has tool calls
    if speech_text.blank? && openrouter_response.tool_calls&.any?
      tool_names = openrouter_response.tool_calls.map do |tc|
        tc.respond_to?(:name) ? tc.name : tc['name']
      end
      speech_text = generate_tool_acknowledgment(tool_names)
      Rails.logger.warn "⚠️ LLM returned empty content with tool calls - using fallback speech"
    end
    
    # SPEECH AMENDMENT: If we have query tool results, call LLM again to amend speech
    query_results = filter_query_tool_results(sync_results, openrouter_response.tool_calls || [])
    if query_results.any?
      speech_text = amend_speech_with_query_results(speech_text, query_results, prompt_data)
    end
    
    # Fallback for completely empty speech
    if speech_text.blank?
      speech_text = "I understand."
    end
    
    {
      id: response_id,
      text: speech_text,
      continue_conversation: narrative[:continue_conversation],
      inner_thoughts: narrative[:inner_thoughts],
      current_mood: narrative[:current_mood],
      pressing_questions: narrative[:pressing_questions],
      model: openrouter_response.model,
      usage: openrouter_response.usage,
      success: true,
      speech_text: speech_text  # Also include as :speech_text for compatibility
    }
  end
  
  def queue_async_tools(async_tools, response_id)
    async_tools.each do |tool_call|
      tool_name = tool_call.respond_to?(:name) ? tool_call.name : tool_call['name']
      arguments = tool_call.respond_to?(:arguments) ? tool_call.arguments : tool_call['arguments']
      
      AsyncToolJob.perform_later(
        tool_name,
        arguments,
        @session_id,
        response_id
      )
    end
  end
  
  def store_conversation_log(conversation, ai_response, sync_results, tool_analysis)
    # Merge narrative metadata if available
    metadata = {
      model_used: ai_response[:model],
      sync_tools: tool_analysis[:sync_tools].map { |t| t.respond_to?(:name) ? t.name : t['name'] },
      async_tools: tool_analysis[:async_tools].map { |t| t.respond_to?(:name) ? t.name : t['name'] },
      response_id: ai_response[:id],
      usage: ai_response[:usage]
    }
    
    # Add narrative metadata if available
    if @narrative_metadata
      Rails.logger.info "📊 Adding narrative metadata: #{@narrative_metadata}"
      metadata.merge!(@narrative_metadata)
    else
      Rails.logger.warn "⚠️ No narrative metadata available to store"
    end
    
    ConversationLog.create!(
      session_id: @session_id,
      user_message: @message,
      ai_response: ai_response[:text],
      tool_results: sync_results.to_json,
      metadata: metadata.to_json
    )
    
    # Update conversation totals
    conversation.update!(
      message_count: conversation.conversation_logs.count,
      continue_conversation: tool_analysis[:async_tools].any?
    )
  end
  
  def format_response_for_hass(ai_response, tool_analysis)
    # Determine response type based on tool usage
    response_type = tool_analysis[:async_tools].any? ? 'action_done' : 'query_answer'
    
    # Build entity lists for tools
    success_entities = build_success_entities(tool_analysis)
    targets = build_targets(tool_analysis)
    
    # Use LLM's continue_conversation OR force true if tools pending
    continue_conversation = ai_response[:continue_conversation] || tool_analysis[:async_tools].any?
    
    # End conversation and queue memory creation if not continuing
    if !continue_conversation
      conversation = Conversation.find_by(session_id: @session_id)
      if conversation && conversation.active?
        conversation.end!
        Rails.logger.info "🧠 Ended conversation: #{@session_id}"
      end
    end
    
    # Store narrative metadata
    store_narrative_metadata(ai_response)
    
    # Create proper ConversationResponse
    conversation_response = ConversationResponse.action_done(
      ai_response[:text],
      success_entities: success_entities,
      targets: targets,
      continue_conversation: continue_conversation,
      conversation_id: @session_id
    )
    
    # Get base response and add end_conversation field
    response = conversation_response.to_home_assistant_response
    response[:end_conversation] = !continue_conversation  # Inverse of continue
    
    Rails.logger.info "📤 Response: continue_conversation=#{continue_conversation}, end_conversation=#{!continue_conversation}"
    
    response
  end
  
  def store_narrative_metadata(ai_response)
    # Store narrative elements in the most recent conversation log
    # This will be created after this method, so we'll update it in store_conversation_log
    @narrative_metadata = {
      inner_thoughts: ai_response[:inner_thoughts],
      current_mood: ai_response[:current_mood],
      pressing_questions: ai_response[:pressing_questions],
      continue_conversation_from_llm: ai_response[:continue_conversation]
    }
  end
  
  private
  
  def extract_narrative_elements(content)
    return default_narrative if content.blank?
    
    Rails.logger.info "🔍 Extracting narrative from content: #{content}"
    
    result = {
      continue_conversation: extract_between_markers(content, "[CONTINUE:", "]") == "true",
      inner_thoughts: extract_between_markers(content, "[THOUGHTS:", "]"),
      current_mood: extract_between_markers(content, "[MOOD:", "]"),
      pressing_questions: extract_between_markers(content, "[QUESTIONS:", "]"),
      speech_text: content.gsub(/\[CONTINUE:.*?\]|\[THOUGHTS:.*?\]|\[MOOD:.*?\]|\[QUESTIONS:.*?\]/m, '').strip
    }
    
    Rails.logger.info "📝 Extracted narrative: #{result}"
    result
  end
  
  def extract_between_markers(text, start_marker, end_marker)
    return nil unless text
    match = text.match(/#{Regexp.escape(start_marker)}(.*?)#{Regexp.escape(end_marker)}/m)
    match ? match[1].strip : nil
  end
  
  def default_narrative
    {
      continue_conversation: false,
      inner_thoughts: nil,
      current_mood: nil,
      pressing_questions: nil,
      speech_text: ""
    }
  end
  
  def generate_tool_acknowledgment(tool_names)
    # Phase 1: Simple generic acknowledgment
    # TODO Phase 2: Make this persona-specific
    "Alright, I'm on it. Let me handle that for you."
  end
  
  def check_and_clear_pending_tools(conversation)
    pending = conversation.flow_data_json&.dig('pending_tools') || []
    return [] if pending.blank?
    
    # Phase 1: Mock success for all pending tools
    # TODO Phase 2: Check actual job status
    results = pending.map do |tool|
      {
        tool: tool['name'],
        success: true,
        message: "Successfully executed #{tool['name']}"
      }
    end
    
    # Clear pending tools after processing
    conversation.update!(flow_data_json: {})
    
    results
  end
  
  def inject_tool_results_into_messages(prompt_data, previous_results)
    return if previous_results.blank?
    
    tool_summary = previous_results.map do |r|
      "#{r[:success] ? '✓' : '✗'} #{r[:tool]}: #{r[:message]}"
    end.join(", ")
    
    system_msg = {
      role: 'system',
      content: "Results from your previous actions: #{tool_summary}. Acknowledge these naturally in your response."
    }
    
    # Insert right before the current user message
    prompt_data[:messages].insert(-1, system_msg)
    
    Rails.logger.info "🔄 Injected tool results: #{tool_summary}"
  end
  
  def store_pending_tools(conversation, async_tools)
    return if async_tools.blank?
    
    conversation.update!(
      flow_data_json: {
        'pending_tools' => async_tools.map { |t| 
          tool_name = t.respond_to?(:name) ? t.name : t['name']
          arguments = t.respond_to?(:arguments) ? t.arguments : t['arguments']
          
          { 
            'name' => tool_name, 
            'arguments' => arguments,
            'queued_at' => Time.current.iso8601
          }
        }
      }
    )
    
    Rails.logger.info "💾 Stored #{async_tools.length} pending tools for next turn"
  end
  
  def build_success_entities(tool_analysis)
    # For async tools, assume they will succeed (they execute in background)
    tool_analysis[:async_tools].map do |tool_call|
      tool_name = tool_call.respond_to?(:name) ? tool_call.name : tool_call['name']
      arguments = tool_call.respond_to?(:arguments) ? tool_call.arguments : tool_call['arguments']
      
      {
        entity_id: arguments['entity_id'] || tool_name,
        name: tool_name.humanize,
        state: 'pending' # Will be updated when async job completes
      }
    end
  end
  
  def build_targets(tool_analysis)
    # Extract entity targets from all tool calls
    all_tools = (tool_analysis[:sync_tools] + tool_analysis[:async_tools])
    
    all_tools.map do |tool_call|
      arguments = tool_call.respond_to?(:arguments) ? tool_call.arguments : tool_call['arguments']
      entity_id = arguments['entity_id']
      
      next unless entity_id
      
      {
        entity_id: entity_id,
        name: entity_id.split('.').last.humanize,
        domain: entity_id.split('.').first
      }
    end.compact
  end
  
  def filter_query_tool_results(sync_results, tool_calls)
    query_results = {}
    
    tool_calls.each do |call|
      tool_name = call.respond_to?(:name) ? call.name : call['name']
      
      # Only include results from query tools
      if Tools::Registry.tool_intent(tool_name) == :query && sync_results[tool_name]
        query_results[tool_name] = sync_results[tool_name]
      end
    end
    
    query_results
  end
  
  def amend_speech_with_query_results(original_speech, query_results, prompt_data)
    # Build query results summary
    results_summary = query_results.map do |tool_name, result|
      if result[:success]
        "#{tool_name}: #{result[:message] || result[:data] || 'completed'}"
      else
        "#{tool_name}: #{result[:error] || 'failed'}"
      end
    end.join(", ")
    
    # Call LLM to amend the speech naturally
    amendment_messages = [
      { role: 'system', content: prompt_data[:system_prompt] },
      { 
        role: 'user', 
        content: "Please amend this response to naturally include the tool results: \"#{original_speech}\"\n\nTool results: #{results_summary}\n\nReturn only the amended speech, staying in character." 
      }
    ]
    
    begin
      amendment_response = LlmService.call_with_tools(
        messages: amendment_messages,
        tools: [], # No tools for amendment call
        model: determine_model_for_conversation
      )
      
      amended_speech = amendment_response.content&.strip
      return amended_speech if amended_speech.present?
    rescue => e
      Rails.logger.warn "Failed to amend speech: #{e.message}"
    end
    
    # Fallback: return original speech if amendment fails
    original_speech
  end
end