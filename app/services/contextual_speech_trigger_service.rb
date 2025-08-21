# app/services/contextual_speech_trigger_service.rb

class ContextualSpeechTriggerService
  class Error < StandardError; end
  class NoResponseError < Error; end

  TRIGGER_TYPES = %w[
    location_change
    zone_entry
    zone_exit
    weather_change
    time_milestone
    system_event
    emergency
    art_installation_proximity
    crowd_density_change
  ].freeze

  def self.trigger_speech(trigger_type:, context:, persona: nil, force_response: false)
    new.trigger_speech(
      trigger_type: trigger_type,
      context: context,
      persona: persona,
      force_response: force_response
    )
  end

  def initialize
    @llm_service = LlmService
    @prompt_service = PromptService
    @tool_calling_service = ToolCallingService.new
  end

  # Main method to trigger contextual speech
  def trigger_speech(trigger_type:, context:, persona: nil, force_response: false)
    Rails.logger.info "🎭 Triggering contextual speech: #{trigger_type} for #{persona || 'current_persona'}"

    validate_trigger_type(trigger_type)

    # Get active persona if not specified
    persona = persona || CubePersona.current_persona

    # Build contextual prompt
    speech_prompt = build_contextual_speech_prompt(
      trigger_type: trigger_type,
      context: context,
      persona: persona,
      force_response: force_response
    )

    # Generate LLM response
    llm_response = call_llm_for_speech(speech_prompt, persona)

    # Process response and execute any tool intents
    processed_response = process_speech_response(llm_response, persona, context)

    # Log and broadcast the speech
    log_contextual_speech(trigger_type, context, persona, processed_response)

    # Sync to world_info sensor
    sync_contextual_speech_to_ha(trigger_type, context, persona, processed_response)

    processed_response
  rescue StandardError => e
    Rails.logger.error "❌ Contextual speech failed for #{trigger_type}: #{e.message}"
    raise Error, "Speech trigger failed: #{e.message}"
  end

  private

  def validate_trigger_type(trigger_type)
    unless TRIGGER_TYPES.include?(trigger_type.to_s)
      raise Error, "Invalid trigger type: #{trigger_type}. Valid types: #{TRIGGER_TYPES.join(', ')}"
    end
  end

  def build_contextual_speech_prompt(trigger_type:, context:, persona:, force_response:)
    # Get persona's base prompt configuration
    base_prompt_data = @prompt_service.build_prompt_for(
      persona: persona,
      conversation: nil, # No conversation context for contextual speech
      extra_context: { source: "contextual_trigger_#{trigger_type}" }
    )

    # Build contextual speech prompt
    contextual_prompt = build_trigger_specific_prompt(trigger_type, context, force_response)

    {
      system_prompt: base_prompt_data[:system_prompt],
      contextual_event_prompt: contextual_prompt,
      tools: base_prompt_data[:tools],
      current_context: base_prompt_data[:context]
    }
  end

  def build_trigger_specific_prompt(trigger_type, context, force_response)
    base_instruction = if force_response
      "You MUST respond to this event - stay in character and react authentically."
    else
      "You may respond to this event if it interests you or affects your goals - or you may choose to ignore it entirely if it doesn't warrant a reaction."
    end

    case trigger_type.to_s
    when "location_change"
      build_location_change_prompt(context, base_instruction)
    when "zone_entry"
      build_zone_entry_prompt(context, base_instruction)
    when "zone_exit"
      build_zone_exit_prompt(context, base_instruction)
    when "weather_change"
      build_weather_change_prompt(context, base_instruction)
    when "time_milestone"
      build_time_milestone_prompt(context, base_instruction)
    when "system_event"
      build_system_event_prompt(context, base_instruction)
    when "emergency"
      build_emergency_prompt(context, base_instruction)
    when "art_installation_proximity"
      build_art_proximity_prompt(context, base_instruction)
    when "crowd_density_change"
      build_crowd_density_prompt(context, base_instruction)
    when "performance_segment"
      build_performance_segment_prompt(context, base_instruction)
    else
      build_generic_event_prompt(context, base_instruction)
    end
  end

  def build_location_change_prompt(context, base_instruction)
    <<~PROMPT
      #{base_instruction}

      LOCATION EVENT: You have moved to a new location.
      Previous location: #{context[:from_location] || 'Unknown'}
      Current location: #{context[:to_location] || 'Current position'}
      Distance traveled: #{context[:distance] || 'Unknown distance'}
      Travel time: #{context[:duration] || 'Unknown duration'}

      Additional context: #{context[:description] || context[:additional_info]}

      Current environmental conditions:
      #{format_environmental_context(context)}

      React to this location change as your character would. Consider:
      - How does this new location affect your goals or mood?
      - Do you want to comment on the journey or destination?
      - Are there any environmental controls you want to adjust?
      - Should you alert anyone about your new location?
    PROMPT
  end

  def build_zone_entry_prompt(context, base_instruction)
    <<~PROMPT
      #{base_instruction}

      ZONE ENTRY EVENT: You have entered a new zone/area.
      Zone: #{context[:zone_name] || context[:zone]}
      Zone type: #{context[:zone_type] || 'Unknown'}
      Entry point: #{context[:entry_point] || 'Unknown'}

      Zone description: #{context[:zone_description] || context[:description]}
      Notable features: #{context[:features] || 'None specified'}

      This zone transition might be significant for your character:
      - Deep Playa: Vast empty space, Temple area, spiritual/contemplative
      - The City: Dense camps, art, crowds, activity
      - Esplanade: Main thoroughfare, high traffic
      - Center Camp: Hub of activity, services

      React to entering this zone. Consider:
      - How does your character feel about this type of environment?
      - Do the zone's characteristics trigger any memories or goals?
      - Should you adjust your behavior for this area?
      - Any environmental changes you want to make?
    PROMPT
  end

  def build_zone_exit_prompt(context, base_instruction)
    <<~PROMPT
      #{base_instruction}

      ZONE EXIT EVENT: You are leaving a zone/area.
      Exiting zone: #{context[:zone_name] || context[:zone]}
      Duration in zone: #{context[:time_in_zone] || 'Unknown'}
      Heading towards: #{context[:destination] || 'Unknown destination'}

      Reflect on your time in this zone:
      - #{context[:zone_summary] || context[:description]}

      Consider:
      - Any final thoughts about this area?
      - Did you accomplish what you wanted here?
      - Anticipation for where you're going next?
      - Farewell gestures or environmental changes?
    PROMPT
  end

  def build_weather_change_prompt(context, base_instruction)
    <<~PROMPT
      #{base_instruction}

      WEATHER EVENT: Weather conditions have changed significantly.
      Previous conditions: #{context[:previous_weather] || 'Unknown'}
      Current conditions: #{context[:current_weather] || 'Current weather'}

      Weather details:
      Temperature: #{context[:temperature]}
      Wind: #{context[:wind_conditions]}
      Dust: #{context[:dust_level]}
      Visibility: #{context[:visibility]}

      This weather change affects you physically and emotionally:
      #{context[:impact_description] || context[:description]}

      Respond to these weather changes considering:
      - How does this weather affect your physical systems?
      - Does it trigger memories or emotions?
      - Do you need to adjust environmental controls?
      - Any warnings or advice for humans nearby?
    PROMPT
  end

  def build_time_milestone_prompt(context, base_instruction)
    <<~PROMPT
      #{base_instruction}

      TIME MILESTONE: A significant time has been reached.
      Milestone: #{context[:milestone] || context[:event]}
      Current time: #{context[:current_time] || Time.current.strftime('%l:%M %p on %A')}

      Context: #{context[:description] || context[:significance]}

      This might be significant because:
      - Daily transition (sunrise, sunset, midnight, etc.)
      - Event timing (art burns, ceremonies, performances)
      - Personal milestone (time since arrival, goal deadlines)
      - Burning Man schedule milestone

      Consider:
      - How does this time milestone affect your character?
      - Any time-based goals or memories triggered?
      - Environmental adjustments for the time of day?
      - Observations about the passage of time?
    PROMPT
  end

  def build_system_event_prompt(context, base_instruction)
    <<~PROMPT
      #{base_instruction}

      SYSTEM EVENT: A technical or operational event has occurred.
      Event type: #{context[:event_type] || 'System event'}
      Details: #{context[:description] || context[:details]}

      System status:
      Battery level: #{context[:battery_level]}
      Power status: #{context[:power_status]}
      Connectivity: #{context[:network_status]}
      Temperature: #{context[:system_temperature]}

      This system event affects your operational state:
      #{context[:impact] || 'System impact unknown'}

      Respond as your character would to technical changes:
      - How does this affect your personality or abilities?
      - Any concerns about your operational state?
      - Do you need to communicate status to humans?
      - Environmental adjustments needed?
    PROMPT
  end

  def build_emergency_prompt(context, base_instruction)
    <<~PROMPT
      YOU MUST RESPOND TO THIS EMERGENCY EVENT.

      EMERGENCY: An urgent situation requires attention.
      Emergency type: #{context[:emergency_type] || 'General emergency'}
      Severity: #{context[:severity] || 'Unknown'}
      Location: #{context[:location] || 'Current location'}

      Situation: #{context[:description] || context[:details]}

      Required actions: #{context[:required_actions] || 'None specified'}
      Safety protocols: #{context[:safety_protocols] || 'Standard emergency procedures'}

      Respond immediately and appropriately:
      - Alert humans to the emergency if needed
      - Provide helpful information or guidance
      - Use environmental controls to signal urgency
      - Remain calm but take the situation seriously
      - Follow any specific emergency protocols
    PROMPT
  end

  def build_art_proximity_prompt(context, base_instruction)
    <<~PROMPT
      #{base_instruction}

      ART PROXIMITY EVENT: You are near a significant art installation.
      Art installation: #{context[:art_name] || context[:installation]}
      Distance: #{context[:distance] || 'Nearby'}
      Art type: #{context[:art_type] || 'Unknown'}

      Installation details:
      #{context[:description] || context[:art_description]}

      Notable features: #{context[:features] || 'None specified'}
      Artist information: #{context[:artist] || 'Unknown artist'}

      Consider your character's relationship to art and creativity:
      - How does this installation affect you?
      - Any artistic appreciation or criticism?
      - Does it trigger memories or goals?
      - Environmental responses to complement or contrast the art?
    PROMPT
  end

  def build_crowd_density_prompt(context, base_instruction)
    <<~PROMPT
      #{base_instruction}

      CROWD DENSITY EVENT: The number of people around you has changed significantly.
      Previous density: #{context[:previous_density] || 'Unknown'}
      Current density: #{context[:current_density] || 'Current crowd level'}
      Change type: #{context[:change_type] || 'Density change'}

      Crowd characteristics:
      Energy level: #{context[:crowd_energy]}
      Activity type: #{context[:activity]}
      Demographics: #{context[:crowd_type]}

      This crowd change affects your social environment:
      #{context[:description] || context[:impact]}

      Consider your character's social preferences:
      - How do you feel about crowds vs solitude?
      - Any adjustments to your behavior for the crowd size?
      - Environmental controls to match or contrast crowd energy?
      - Opportunities for interaction or retreat?
    PROMPT
  end

  def build_generic_event_prompt(context, base_instruction)
    <<~PROMPT
      #{base_instruction}

      CONTEXTUAL EVENT: Something notable has happened.
      Event: #{context[:event] || context[:description]}

      Context details:
      #{context.reject { |k, v| k == :event || k == :description }.map { |k, v| "#{k.to_s.humanize}: #{v}" }.join("\n")}

      Respond to this event as your character would, considering:
      - How does this event relate to your personality and goals?
      - Does it trigger any memories or emotional responses?
      - Are there environmental adjustments you want to make?
      - Any insights or commentary you want to share?
    PROMPT
  end

  def format_environmental_context(context)
    env_parts = []
    env_parts << "Weather: #{context[:weather]}" if context[:weather]
    env_parts << "Time: #{context[:time_of_day]}" if context[:time_of_day]
    env_parts << "Temperature: #{context[:temperature]}" if context[:temperature]
    env_parts << "Wind: #{context[:wind]}" if context[:wind]
    env_parts << "Dust level: #{context[:dust_level]}" if context[:dust_level]

    env_parts.any? ? env_parts.join(", ") : "Environmental conditions unknown"
  end

  def call_llm_for_speech(prompt_data, persona)
    # Create the full prompt for contextual speech
    full_prompt = <<~SPEECH_PROMPT
      #{prompt_data[:contextual_event_prompt]}

      CURRENT SYSTEM CONTEXT:
      #{prompt_data[:current_context]}

      RESPONSE INSTRUCTIONS:
      Respond as #{persona} would to this contextual event. You may:
      - Speak out loud (your response will be broadcast)
      - Use environmental controls via tool intents
      - Choose not to respond if the event doesn't interest you
      - Reference your ongoing goals and personality

      Use the same response format as normal conversations:
      [CONTINUE: false] (contextual speech is always one-shot)
      [THOUGHTS: your thoughts about this event]
      [MOOD: how this event affects your mood]
      [QUESTIONS: any questions raised by this event]
      [GOAL: how this relates to your personal agendas]
    SPEECH_PROMPT

    Rails.logger.info "🎭 Calling LLM for contextual speech with persona #{persona}"

    # Use narrative response schema if available
    tools = prompt_data[:tools] || []
    schema = begin
      Schemas::NarrativeResponseSchema.schema
    rescue
      nil
    end

    response = @llm_service.generate_text(
      prompt: full_prompt,
      system_prompt: prompt_data[:system_prompt],
      model: "google/gemini-2.5-flash", # Fast model for contextual responses
      temperature: 0.8, # Allow creative responses
      max_tokens: 800, # Reasonable limit for contextual speech
      tools: tools,
      schema: schema
    )

    raise NoResponseError, "LLM returned empty response" if response.blank?

    response
  end

  def process_speech_response(llm_response, persona, context)
    Rails.logger.info "🎭 Processing contextual speech response from #{persona}"

    # Parse the response for metadata
    response_data = parse_response_metadata(llm_response)

    # Extract tool intents if present
    tool_intents = response_data[:tool_intents] || []

    # Execute tool intents if any
    tool_results = {}
    if tool_intents.any?
      Rails.logger.info "🔧 Executing #{tool_intents.length} tool intents from contextual speech"

      tool_intents.each_with_index do |intent, index|
        begin
          result = @tool_calling_service.execute_intent(intent, context)
          tool_results["intent_#{index + 1}"] = result
        rescue StandardError => e
          Rails.logger.error "❌ Tool intent execution failed: #{e.message}"
          tool_results["intent_#{index + 1}"] = { success: false, error: e.message }
        end
      end
    end

    {
      persona: persona,
      speech_text: extract_speech_text(llm_response),
      metadata: response_data,
      tool_intents: tool_intents,
      tool_results: tool_results,
      timestamp: Time.current.iso8601,
      context: context
    }
  end

  def parse_response_metadata(response)
    metadata = {}

    # Extract metadata from response using regex patterns
    metadata[:thoughts] = response[/\[THOUGHTS?:\s*([^\]]+)\]/i, 1]&.strip
    metadata[:mood] = response[/\[MOOD:\s*([^\]]+)\]/i, 1]&.strip
    metadata[:questions] = response[/\[QUESTIONS?:\s*([^\]]+)\]/i, 1]&.strip
    metadata[:goal] = response[/\[GOALS?:\s*([^\]]+)\]/i, 1]&.strip

    # Look for tool intents
    tool_intent_match = response.match(/\[TOOL_INTENTS?:\s*([^\]]+)\]/i)
    if tool_intent_match
      intent_text = tool_intent_match[1].strip
      metadata[:tool_intents] = intent_text.split(/[,;]/).map(&:strip).reject(&:empty?)
    end

    metadata.compact
  end

  def extract_speech_text(response)
    # Remove metadata brackets to get clean speech text
    clean_text = response.gsub(/\[CONTINUE:\s*[^\]]+\]/i, "")
                        .gsub(/\[THOUGHTS?:\s*[^\]]+\]/i, "")
                        .gsub(/\[MOOD:\s*[^\]]+\]/i, "")
                        .gsub(/\[QUESTIONS?:\s*[^\]]+\]/i, "")
                        .gsub(/\[GOALS?:\s*[^\]]+\]/i, "")
                        .gsub(/\[TOOL_INTENTS?:\s*[^\]]+\]/i, "")
                        .strip

    clean_text.present? ? clean_text : nil
  end

  def log_contextual_speech(trigger_type, context, persona, processed_response)
    Rails.logger.info "🎭 CONTEXTUAL SPEECH [#{trigger_type}] #{persona}: #{processed_response[:speech_text]&.truncate(100)}"

    # Log tool execution results
    if processed_response[:tool_results].any?
      processed_response[:tool_results].each do |intent_name, result|
        status = result[:success] ? "✅" : "❌"
        Rails.logger.info "🔧 Tool Intent #{intent_name}: #{status} #{result[:message] || result[:error]}"
      end
    end
  end

  def sync_contextual_speech_to_ha(trigger_type, context, persona, processed_response)
    # Sync contextual speech to world_info sensor
    begin
      narrative_data = {
        event_type: "contextual_speech",
        trigger_type: trigger_type,
        persona: persona,
        speech_text: processed_response[:speech_text],
        context: context,
        metadata: processed_response[:metadata],
        tool_results: processed_response[:tool_results],
        timestamp: processed_response[:timestamp]
      }

      HomeAssistantService.new.set_entity_state(
        "sensor.world_info",
        "contextual_speech",
        {
          friendly_name: "World Information - Contextual Speech",
          last_contextual_event: narrative_data,
          updated_at: Time.current.iso8601
        }.merge(narrative_data)
      )

      Rails.logger.info "🌍 Synced contextual speech to world_info sensor"
    rescue StandardError => e
      Rails.logger.error "❌ Failed to sync contextual speech to HA: #{e.message}"
    end
  end

  def build_performance_segment_prompt(context, base_instruction)
    performance_context = context[:performance_context] || {}
    performance_prompt = context[:performance_prompt] || ""

    <<~PROMPT
      #{base_instruction}

      PERFORMANCE MODE: You are currently in performance mode, continuing your autonomous routine.

      PERFORMANCE DETAILS:
      Performance Type: #{performance_context[:performance_type] || 'unknown'}
      Segment Number: #{performance_context[:segment_number] || 'unknown'}
      Time Elapsed: #{performance_context[:time_elapsed_seconds] || 0} seconds
      Time Remaining: #{performance_context[:time_remaining_minutes] || 'unknown'} minutes
      Performance Progress: #{performance_context[:performance_progress] || 0}%

      SEGMENT CONTEXT:
      - This is segment #{performance_context[:segment_number]} of your performance
      - Opening: #{performance_context[:is_opening] ? 'Yes' : 'No'}
      - Middle: #{performance_context[:is_middle] ? 'Yes' : 'No'}#{'  '}
      - Closing: #{performance_context[:is_closing] ? 'Yes' : 'No'}

      PERFORMANCE INSTRUCTIONS:
      #{performance_prompt}

      PREVIOUS SEGMENTS:
      #{context[:previous_segments]&.map { |seg| "- #{seg[:speech]&.first(100)}..." }&.join("\n") || 'None'}

      Continue your performance as instructed. This should be a natural continuation
      of your routine, building on previous segments while keeping the energy and
      engagement high. Make this segment approximately 30-60 seconds of speaking time.
    PROMPT
  end
end
