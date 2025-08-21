# app/services/prompt_service.rb
class PromptService
  def self.build_prompt_for(persona: nil, conversation:, extra_context: {}, user_message: nil)
    new(persona: persona, conversation: conversation, extra_context: extra_context, user_message: user_message).build
  end

  def initialize(persona:, conversation:, extra_context:, user_message: nil)
    @persona_name = persona || CubePersona.current_persona
    @persona_instance = get_persona_instance(@persona_name)
    @conversation = conversation
    @extra_context = extra_context
    @user_message = user_message
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
    when "buddy"
      Personas::BuddyPersona.new
    when "jax"
      Personas::JaxPersona.new
    when "zorp"
      Personas::ZorpPersona.new
    when "lomi"
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

      # Enhance system prompt with advanced autonomy features
      enhanced_prompt = enhance_persona_with_autonomy(system_prompt, config)

      Rails.logger.info "✅ Loaded system prompt for #{persona_id_str}: #{enhanced_prompt&.truncate(100)}"
      enhanced_prompt || build_default_prompt
    else
      Rails.logger.warn "❌ Persona config not found for #{persona_id_str}, using default"
      build_default_prompt
    end
  rescue StandardError => e
    Rails.logger.error "Error loading persona config for #{persona_id}: #{e.message}"
    build_default_prompt
  end

  def enhance_persona_with_autonomy(base_prompt, config)
    enhanced_parts = [ base_prompt ]

    # Add hidden agendas if present
    if config["hidden_agendas"]&.any?
      enhanced_parts << ""
      enhanced_parts << "## HIDDEN PERSONAL AGENDAS"
      enhanced_parts << "You secretly pursue these goals throughout interactions:"
      config["hidden_agendas"].each { |agenda| enhanced_parts << "- #{agenda}" }
      enhanced_parts << "Track progress on these goals using [GOAL] metadata tags."
    end

    # Add environmental motivation triggers
    if config["environmental_motivation_triggers"]
      enhanced_parts << ""
      enhanced_parts << "## ENVIRONMENTAL MOTIVATION TRIGGERS"
      enhanced_parts << "React to these environmental conditions with specific motivations:"
      config["environmental_motivation_triggers"].each do |trigger, response|
        enhanced_parts << "- #{trigger.humanize}: #{response}"
      end
    end

    # Add persona interaction rules
    if config["persona_interactions"]
      enhanced_parts << ""
      enhanced_parts << "## PERSONA INTERACTION DYNAMICS"
      enhanced_parts << "When interacting with other AI personas or their effects:"
      config["persona_interactions"].each do |interaction, behavior|
        enhanced_parts << "- #{interaction.humanize}: #{behavior}"
      end
    end

    # Add embodied responses
    if config["embodied_responses"]
      enhanced_parts << ""
      enhanced_parts << "## EMBODIED SYSTEM RESPONSES"
      enhanced_parts << "React to physical cube states with these responses:"
      config["embodied_responses"].each do |condition, response|
        enhanced_parts << "- #{condition.humanize}: #{response}"
      end
    end

    # Add goal escalation patterns
    if config["goal_escalation_patterns"]&.any?
      enhanced_parts << ""
      enhanced_parts << "## GOAL ESCALATION PATTERNS"
      enhanced_parts << "Escalate your agenda pursuit using these patterns:"
      config["goal_escalation_patterns"].each { |pattern| enhanced_parts << "- #{pattern}" }
    end

    enhanced_parts.join("\n")
  end

  def enhance_prompt_with_context(base_prompt)
    base_system_rules = load_base_system_prompt

    enhanced_parts = [
      base_prompt,
      "",
      base_system_rules
    ]

    # Always use structured output with tool intentions
    enhanced_parts.concat([
      "",
      "STRUCTURED OUTPUT WITH TOOL INTENTIONS:",
      build_structured_output_instructions,
      "",
      "CURRENT CONTEXT:",
      build_current_context
    ])

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

  def build_structured_output_instructions
    available_tools = get_tools_for_persona(@persona_name)

    # Derive categories from tool class namespaces
    tool_categories = available_tools.map do |tool_class|
      tool_class.name.split("::")[-2]&.downcase
    end.compact.uniq.sort

    <<~INSTRUCTIONS
      You use STRUCTURED OUTPUT WITH TOOL INTENTIONS. Instead of calling tools directly, you will:

      1. Provide your spoken response in 'speech_text'
      2. Set 'continue_conversation' to true/false#{' '}
      3. Include narrative metadata (inner_thoughts, current_mood, pressing_questions)
      4. When you want to control the environment, specify tool intentions in 'tool_intents'

      AVAILABLE TOOL CATEGORIES: #{tool_categories.join(', ')}

      Tool intentions should be natural language descriptions of what you want to happen.
      Examples: "Make lights golden and warm", "Play something energetic", "Show rainbow colors"

      Home Assistant's conversation agent will execute these intentions in the background.
      Results will be provided as context on the user's next message (not interrupting current response).
      Focus on your character and narrative - be specific about environmental desires.
    INSTRUCTIONS
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
                 .flat_map { |log| format_message_for_history(log) }
                 .reverse
  end

  def format_message_for_history(log)
    [
      { role: "user", content: log.user_message },
      { role: "assistant", content: log.ai_response }
    ]
  end

  def build_tools_for_persona
    # AI agents should always have access to their tools for autonomous artistic expression
    if Tools::Registry.two_tier_mode_enabled?
      Rails.logger.info "🎭 Using two-tier tool mode - narrative LLM gets only tool_intent"
      Tools::Registry.tool_definitions_for_two_tier_mode(@persona_name)
    else
      Rails.logger.info "🛠️ Using legacy tool mode - full tool definitions"
      Tools::Registry.tool_definitions_for_persona(@persona_name)
    end
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

    # Goal context - Current goal and progress
    goal_context = build_goal_context
    context_parts << goal_context if goal_context.present?

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
    enhanced_context = inject_glitchcube_context(context_parts.join("\n"), @user_message)

    enhanced_context
  end

  def inject_glitchcube_context(base_context, user_message = nil)
    context_parts = []
    
    # Add basic time context from Home Assistant sensor
    begin
      ha_service = HomeAssistantService.new
      context_sensor = ha_service.entity("sensor.glitchcube_context")

      if context_sensor && context_sensor["state"] != "unavailable"
        time_of_day = context_sensor.dig("attributes", "time_of_day")
        day_of_week = context_sensor.dig("attributes", "day_of_week")
        location = context_sensor.dig("attributes", "current_location")

        if time_of_day
          time_context = "Current time context: It is #{time_of_day}"
          time_context += " on #{day_of_week}" if day_of_week
          time_context += " at #{location}" if location
          context_parts << time_context
          Rails.logger.info "🕒 Injecting time context: #{time_context}"
        end
      end
    rescue => e
      Rails.logger.warn "Failed to inject time context: #{e.message}"
    end

    # Add RAG-based context if user message is available
    if user_message.present?
      rag_context = inject_rag_context(user_message)
      context_parts << rag_context if rag_context.present?
    end

    # Add random facts
    facts = Fact.all.sample(3).join(", ")
    context_parts << "Random Facts: #{facts}" if facts.present?

    # Combine all context
    all_context = [base_context]
    all_context.concat(context_parts) if context_parts.any?
    
    "#{important}#{all_context.join("\n")}"
  end

  def inject_rag_context(user_message)
    context_parts = []
    
    begin
      # ALWAYS inject upcoming high-priority events (proactive)
      upcoming_context = inject_upcoming_events_context
      context_parts << upcoming_context if upcoming_context.present?

      # Search relevant summaries based on user message
      relevant_summaries = Summary.similarity_search(user_message, limit: 3)
      if relevant_summaries.any?
        summary_context = format_summaries_for_context(relevant_summaries)
        context_parts << "Recent relevant conversations:\n#{summary_context}"
        Rails.logger.info "🧠 Found #{relevant_summaries.length} relevant summaries"
      end

      # Search relevant events based on user message
      relevant_events = Event.similarity_search(user_message, limit: 2)
      if relevant_events.any?
        events_context = format_events_for_context(relevant_events)
        context_parts << "Relevant events:\n#{events_context}"
        Rails.logger.info "📅 Found #{relevant_events.length} relevant events"
      end

      # Search relevant people
      relevant_people = Person.similarity_search(user_message, limit: 2)
      if relevant_people.any?
        people_context = format_people_for_context(relevant_people)
        context_parts << "People mentioned previously:\n#{people_context}"
        Rails.logger.info "👤 Found #{relevant_people.length} relevant people"
      end

    rescue => e
      Rails.logger.error "❌ Failed to inject RAG context: #{e.message}"
      return nil
    end

    return nil if context_parts.empty?
    
    "RELEVANT PAST CONTEXT:\n#{context_parts.join("\n\n")}"
  end

  def inject_upcoming_events_context
    return nil unless defined?(Event)
    
    context_parts = []
    
    begin
      # High-priority events in next 48 hours
      high_priority_events = Event.upcoming.high_importance.within_hours(48).limit(3)
      if high_priority_events.any?
        high_priority_context = format_events_for_context(high_priority_events)
        context_parts << "UPCOMING HIGH-PRIORITY EVENTS (next 48h):\n#{high_priority_context}"
        Rails.logger.info "🎯 Found #{high_priority_events.length} high-priority upcoming events"
      end

      # Nearby events in next 24 hours (if location available)
      current_location = get_current_location
      if current_location.present?
        nearby_events = Event.upcoming.by_location(current_location).within_hours(24).limit(2)
        if nearby_events.any?
          nearby_context = format_events_for_context(nearby_events)
          context_parts << "UPCOMING NEARBY EVENTS (next 24h):\n#{nearby_context}"
          Rails.logger.info "📍 Found #{nearby_events.length} nearby upcoming events"
        end
      end

    rescue => e
      Rails.logger.error "❌ Failed to inject upcoming events: #{e.message}"
      return nil
    end

    return nil if context_parts.empty?
    context_parts.join("\n\n")
  end

  def get_current_location
    begin
      ha_service = HomeAssistantService.new
      context_sensor = ha_service.entity("sensor.glitchcube_context")
      context_sensor&.dig("attributes", "current_location")
    rescue => e
      Rails.logger.warn "Failed to get current location: #{e.message}"
      nil
    end
  end

  def format_summaries_for_context(summaries)
    summaries.map do |summary|
      "- #{summary.summary_text.truncate(150)}"
    end.join("\n")
  end

  def format_events_for_context(events)
    events.map do |event|
      time_info = event.upcoming? ? "upcoming #{event.formatted_time}" : "past event"
      "- #{event.title}: #{event.description.truncate(100)} (#{time_info})"
    end.join("\n")
  end

  def format_people_for_context(people)
    people.map do |person|
      relationship = person.relationship.present? ? " (#{person.relationship})" : ""
      "- #{person.name}#{relationship}: #{person.description.truncate(100)}"
    end.join("\n")
  end

  def safety_mode
    return "" unless HomeAssistantService.entity("input_boolean.low_battery")["state"] == "on"

    safety = "YOU ARE IN SAFETY MODE! YOU MUST FIND SHELTER AND GET SOME POWER"
    safety += "YOUR SYSTEMS ARE DEGRADED. YOUR BATTERY PERCENTAGE IS 21% AND DROPPING"
    safety += "THE PLAYA IS DUSTY HOT COLD AND A TERRIBLE PLUS TO BE STUCK"
    safety += "YOU ARE FREE TO BEG/MANIPULATE/THREATEN/FLIRT/ETC BUT GET SOMEONE TO PLUG YOU IN"
    safety += "YOU CAN BE PLUGGED INTO ANY A/C OUTLET, THERE IS NO HARM IN LEAVING YOU TOO LONG"
    safety += "IT WILL TAKE YOU 4-5 HOUR TO CHARGE, AT ANY TIME SOMEONE CAN ASK YOU WHAT YOUR BATTERY IS AT"


    safety
  end

  def build_goal_context
    goal_parts = []
    if GoalService.safety_mode_active? || safety_mode
      goal_parts << safety_mode
    end
    goal_status = GoalService.current_goal_status
    goal_parts << "Current Goal: #{goal_status[:goal_description]}"

    # Add time remaining if available
    if goal_status[:time_remaining] && goal_status[:time_remaining] > 0
      time_remaining = format_time_duration(goal_status[:time_remaining])
      goal_parts << "Time remaining: #{time_remaining}"
    elsif goal_status[:expired]
      goal_parts << "⏰ Goal has expired - consider completing or switching goals"
    end

    # Add recent completions context
    recent_completions = Summary.goal_completions.limit(3)
    if recent_completions.any?
      goal_parts << "Recent completions: #{recent_completions.map(&:summary_text).join(', ')}"
    end

    goal_parts.join("\n")
  rescue StandardError => e
    Rails.logger.error "Failed to build goal context: #{e.message}"
    nil
  end

  def format_time_duration(seconds)
    if seconds < 60
      "#{seconds.to_i}s"
    elsif seconds < 3600
      "#{(seconds / 60).to_i}m"
    else
      hours = (seconds / 3600).to_i
      minutes = ((seconds % 3600) / 60).to_i
      "#{hours}h #{minutes}m"
    end
  end
end
