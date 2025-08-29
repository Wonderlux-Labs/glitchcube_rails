# frozen_string_literal: true

# ProactiveMessageService
# Generates contextual, persona-aware proactive messages using LLM
class ProactiveMessageService
  class Error < StandardError; end

  def self.generate(trigger_type:, context: nil)
    new(trigger_type: trigger_type, context: context).generate
  end

  def initialize(trigger_type:, context: nil)
    @trigger_type = trigger_type
    @context = context || {}
  end

  def generate
    Rails.logger.info "🤖 Generating proactive message for trigger: #{@trigger_type}"

    # Get current system context
    system_context = gather_system_context

    # Generate message with LLM
    result = generate_with_llm(system_context)

    {
      message: result["message"],
      persona: result["persona"] || determine_persona,
      satellite_entity: determine_satellite_entity(result["persona"]),
      should_announce: result["should_announce"] != false
    }
  rescue StandardError => e
    Rails.logger.error "❌ ProactiveMessageService failed: #{e.message}"
    fallback_message
  end

  private

  def gather_system_context
    context = {
      trigger_type: @trigger_type,
      time: Time.current.strftime("%A %I:%M %p"),
      provided_context: @context
    }

    # Add current goal if available
    begin
      goal_status = GoalService.current_goal_status
      context[:current_goal] = goal_status[:goal_description] if goal_status
    rescue StandardError => e
      Rails.logger.debug "Could not get goal status: #{e.message}"
    end

    # Add location context if available
    begin
      gps_service = Services::Gps::GPSTrackingService.new
      location = gps_service.current_location
      context[:location] = {
        zone: location[:zone],
        address: location[:address]
      } if location
    rescue StandardError => e
      Rails.logger.debug "Could not get location: #{e.message}"
    end

    context
  end

  def generate_with_llm(system_context)
    prompt = build_prompt(system_context)
    
    response = LlmService.generate_text(
      prompt: prompt,
      system_prompt: build_system_prompt,
      model: "google/gemini-2.5-flash",
      temperature: 0.7,
      max_tokens: 500
    )

    parse_response(response)
  rescue StandardError => e
    Rails.logger.error "❌ LLM generation failed: #{e.message}"
    raise Error, "Failed to generate proactive message: #{e.message}"
  end

  def build_system_prompt
    <<~PROMPT
      You are generating proactive announcements for a Burning Man AI assistant. Create natural, contextual messages that feel organic rather than robotic.

      Based on the trigger type and context, generate:
      1. **message** - What the AI should say (be natural and engaging)
      2. **persona** - Which persona fits this situation best (buddy, crashoverride, sparkle, sage, etc.)
      3. **should_announce** - Whether to actually speak (false if no one is around or inappropriate timing)

      Personas:
      - **buddy**: Friendly, helpful, enthusiastic 
      - **crashoverride**: Edgy hacker, glitchy, mischievous
      - **sparkle**: Bubbly, magical, whimsical
      - **sage**: Wise, contemplative, philosophical

      Return JSON format:
      {
        "message": "Hey there! I noticed some movement - everything cool?",
        "persona": "buddy", 
        "should_announce": true
      }

      Keep messages conversational and appropriate for the context. Consider time of day, location, and situation.
    PROMPT
  end

  def build_prompt(system_context)
    <<~PROMPT
      Generate a proactive message for this situation:

      **Trigger:** #{@trigger_type}
      **Time:** #{system_context[:time]}
      **Context:** #{@context}

      #{format_additional_context(system_context)}

      Create a natural message that fits the situation. Consider:
      - Is this a good time to speak up?
      - What persona would handle this best?
      - How can I be helpful or engaging without being annoying?

      Trigger types and suggested approaches:
      - **motion_detected**: Casual greeting or check-in
      - **event_reminder**: Friendly reminder about upcoming events
      - **goal_check_in**: Encouraging progress update
      - **system_startup**: Announce presence/availability
      - **location_change**: Comment on new location or offer local info
      - **time_based**: Time-appropriate suggestions or observations
    PROMPT
  end

  def format_additional_context(system_context)
    parts = []
    
    if system_context[:current_goal]
      parts << "**Current Goal:** #{system_context[:current_goal]}"
    end
    
    if system_context[:location]
      parts << "**Location:** #{system_context[:location][:zone]} - #{system_context[:location][:address]}"
    end
    
    parts.empty? ? "" : parts.join("\n")
  end

  def parse_response(response)
    # Remove markdown code blocks if present
    cleaned = response.gsub(/```json\s*\n?/, "").gsub(/```\s*$/, "").strip
    
    JSON.parse(cleaned)
  rescue JSON::ParserError => e
    Rails.logger.error "❌ Failed to parse proactive message JSON: #{e.message}"
    Rails.logger.error "Response was: #{response}"
    
    # Fallback parsing
    {
      "message" => extract_message_fallback(response),
      "persona" => determine_persona,
      "should_announce" => true
    }
  end

  def extract_message_fallback(response)
    # Try to extract a reasonable message from malformed JSON
    if response.include?('"message"')
      match = response.match(/"message":\s*"([^"]+)"/i)
      return match[1] if match
    end
    
    # Last resort - use a cleaned version of the response
    response.gsub(/[{}"\[\]]/, "").strip.truncate(200)
  end

  def determine_persona
    case @trigger_type.to_s
    when /motion|greeting/
      "buddy"
    when /system|startup|error/
      "crashoverride"
    when /event|celebration/
      "sparkle"
    when /goal|time|reminder/
      "sage"
    else
"buddy"
    end
  end

  def determine_satellite_entity(persona)
    # Map personas to specific TTS entities/voices
    case persona
    when "crashoverride"
      "assist_satellite.crash_voice"
    when "sparkle"
      "assist_satellite.sparkle_voice" 
    when "sage"
      "assist_satellite.sage_voice"
    else
      "assist_satellite.square_voice" # buddy default
    end
  end

  def fallback_message
    {
      message: "System active and ready.",
      persona: "buddy",
      satellite_entity: "assist_satellite.square_voice",
      should_announce: true
    }
  end
end