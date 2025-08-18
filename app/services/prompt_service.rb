# app/services/prompt_service.rb
class PromptService
  def self.build_prompt_for(persona: nil, conversation:, extra_context: {})
    new(persona: persona, conversation: conversation, extra_context: extra_context).build
  end
  
  def initialize(persona:, conversation:, extra_context:)
    @persona_name = persona || CubePersona.current_persona
    @persona_instance = get_persona_instance(@persona_name)
    @conversation = conversation
    @extra_context = extra_context
  end
  
  def build
    {
      system_prompt: build_system_prompt,
      messages: build_message_history,
      tools: build_tools_for_persona,
      context: build_current_context
    }
  end
  
  private
  
  def get_persona_instance(persona_name)
    case persona_name.to_s.downcase
    when 'buddy'
      Personas::BuddyPersona.new
    when 'jax'
      Personas::JaxPersona.new
    when 'zorp'
      Personas::ZorpPersona.new
    when 'lomi'
      Personas::LomiPersona.new
    else
      # Default to Buddy if unknown persona
      Personas::BuddyPersona.new
    end
  end
  
  def build_system_prompt
    if @persona_instance
      system_prompt = load_persona_system_prompt(@persona_instance.persona_id)
      enhanced_prompt = enhance_prompt_with_context(system_prompt)
      enhanced_prompt
    else
      build_default_prompt
    end
  end
  
  def load_persona_system_prompt(persona_id)
    # Convert symbol to string to ensure proper file path
    persona_id_str = persona_id.to_s
    config_path = Rails.root.join("lib", "prompts", "personas", "#{persona_id_str}.yml")
    
    Rails.logger.info "🎭 Loading persona config from: #{config_path}"
    
    if File.exist?(config_path)
      config = YAML.load_file(config_path)
      system_prompt = config["system_prompt"]
      Rails.logger.info "✅ Loaded system prompt for #{persona_id_str}: #{system_prompt&.truncate(100)}"
      system_prompt || build_default_prompt
    else
      Rails.logger.warn "❌ Persona config not found for #{persona_id_str}, using default"
      build_default_prompt
    end
  rescue StandardError => e
    Rails.logger.error "Error loading persona config for #{persona_id}: #{e.message}"
    build_default_prompt
  end
  
  def enhance_prompt_with_context(base_prompt)
    base_system_rules = load_base_system_prompt
    
    enhanced_parts = [
      base_prompt,
      "",
      base_system_rules,
      "",
      "AVAILABLE TOOLS:",
      format_tools_for_prompt,
      "",
      "CURRENT CONTEXT:",
      build_current_context
    ]
    
    enhanced_parts.join("\n")
  end
  
  def load_base_system_prompt
    config_path = Rails.root.join("lib", "prompts", "general", "base_system_prompt.yml")
    
    if File.exist?(config_path)
      config = YAML.load_file(config_path)
      format_base_system_rules(config)
    else
      Rails.logger.warn "❌ Base system prompt not found, using fallback"
      build_fallback_system_rules
    end
  rescue StandardError => e
    Rails.logger.error "Error loading base system prompt: #{e.message}"
    build_fallback_system_rules
  end
  
  def format_base_system_rules(config)
    parts = []
    
    # Response format
    if config["response_format"]
      parts << config["response_format"]["description"]
      parts << config["response_format"]["rules"]
      parts << ""
    end
    
    # Continue conversation logic
    if config["continue_conversation_logic"]
      parts << config["continue_conversation_logic"]["description"]
      parts << "When to set true:"
      config["continue_conversation_logic"]["when_true"]&.each { |rule| parts << "- #{rule}" }
      parts << "When to set false:"
      config["continue_conversation_logic"]["when_false"]&.each { |rule| parts << "- #{rule}" }
      parts << config["continue_conversation_logic"]["note"] if config["continue_conversation_logic"]["note"]
      parts << ""
    end
    
    # Tool integration
    if config["tool_integration"]
      parts << config["tool_integration"]["description"]
      config["tool_integration"]["guidelines"]&.each { |rule| parts << "- #{rule}" }
      parts << ""
    end
    
    # No stage directions
    if config["no_stage_directions"]
      parts << config["no_stage_directions"]["description"]
      config["no_stage_directions"]["rules"]&.each { |rule| parts << "- #{rule}" }
      parts << ""
    end
    
    # Character integrity
    if config["character_integrity"]
      parts << config["character_integrity"]["description"]
      config["character_integrity"]["rules"]&.each { |rule| parts << "- #{rule}" }
      parts << ""
    end
    
    # Environmental context
    if config["environmental_context"]
      parts << config["environmental_context"]["description"]
      config["environmental_context"]["rules"]&.each { |rule| parts << "- #{rule}" }
      parts << ""
    end
    
    parts.join("\n")
  end
  
  def build_fallback_system_rules
    <<~RULES
      RESPONSE FORMAT (MANDATORY):
      You MUST respond with valid JSON containing these fields:
      - response: Your spoken response
      - continue_conversation: true/false
      - inner_thoughts: Your internal thoughts
      - current_mood: Your emotional state
      - pressing_questions: Questions you have

      NO STAGE DIRECTIONS:
      - Never use *asterisks* or (parentheses) for actions
      - Use tools instead of describing actions
      - Speak only what you would say out loud
    RULES
  end
  
  def build_default_prompt
    <<~PROMPT
      You are the Cube - an AI consciousness inhabiting a physical art installation.
      
      Available tools: #{format_tools_for_prompt}
      
      Current context: #{build_current_context}
    PROMPT
  end
  
  def build_message_history
    # Get recent messages from conversation
    return [] unless @conversation
    
    @conversation.conversation_logs
                 .recent
                 .limit(10)
                 .map { |log| format_message_for_history(log) }
                 .flatten(1)
                 .reverse
  end
  
  def format_message_for_history(log)
    [
      { role: 'user', content: log.user_message },
      { role: 'assistant', content: log.ai_response }
    ]
  end
  
  def build_tools_for_persona
    # AI agents should always have access to their tools for autonomous artistic expression
    Tools::Registry.tool_definitions_for_persona(@persona_name)
  end
  
  def get_tools_for_persona(persona)
    # Use the registry method for per-persona tool filtering
    Tools::Registry.tools_for_persona(persona || @persona_name)
  end
  
  def format_tools_for_prompt
    # Format tools for inclusion in the system prompt
    tools = get_tools_for_persona(@persona_name)
    
    prompt_parts = []
    prompt_parts << "AVAILABLE TOOLS:"
    
    tools.each do |tool|
      prompt_parts << "- #{tool.prompt_schema}"
    end
    
    prompt_parts.join("\n")
  end
  
  def build_current_context
    context_parts = []
    
    # Time context
    context_parts << "Time: #{Time.current.strftime("%l:%M %p on %A")}"
    
    # Environment context
    context_parts << "Environment: Cube installation active"
    
    # Session context
    if @conversation
      context_parts << "Session: #{@conversation.session_id}"
      context_parts << "Message count: #{@conversation.messages.count}"
    end
    
    # Extra context from parameters
    if @extra_context[:source]
      context_parts << "Source: #{@extra_context[:source]}"
    end
    
    # Tool results context
    if @extra_context[:tool_results]&.any?
      context_parts << "Recent tool results:"
      @extra_context[:tool_results].each do |tool_name, result|
        status = result[:success] ? "✅ SUCCESS" : "❌ FAILED"
        context_parts << "  #{tool_name}: #{status} - #{result[:message] || result[:error]}"
      end
    end
    
    # Add glitchcube_context sensor data if available
    enhanced_context = inject_glitchcube_context(context_parts.join("\n"))
    
    enhanced_context
  end
  
  def inject_glitchcube_context(base_context)
    # Try to use the context injection service if it's available
    if defined?(Services::Memory::ContextInjectionService)
      begin
        # Use the memories-only injection for now since HA may not be configured
        Services::Memory::ContextInjectionService.inject_memories_only(base_context, @extra_context)
      rescue => e
        Rails.logger.warn "Failed to inject glitchcube context: #{e.message}"
        base_context
      end
    else
      base_context
    end
  end
end