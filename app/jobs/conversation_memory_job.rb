# frozen_string_literal: true

class ConversationMemoryJob < ApplicationJob
  queue_as :default

  def perform(session_id)
    Rails.logger.info "🧠 Creating memories for session: #{session_id}"

    conversation = Conversation.find_by(session_id: session_id)
    return unless conversation&.ended_at

    # Only create memories for conversations with multiple messages
    logs = conversation.conversation_logs.order(:created_at)
    return if logs.count < 2

    # Get environmental context
    context = fetch_environmental_context

    # Extract memorable insights from the conversation
    memories = extract_conversation_memories(conversation, logs, context)

    # Create ConversationMemory records
    memories.each do |memory_data|
      ConversationMemory.create!(
        session_id: session_id,
        summary: memory_data[:summary],
        memory_type: memory_data[:type],
        importance: memory_data[:importance],
        metadata: memory_data[:metadata].to_json
      )
    end

    Rails.logger.info "✅ Created #{memories.count} memories for session: #{session_id}"
  end

  private

  def hass
   @hass ||= HomeAssistantService
  end

  def fetch_environmental_context
    context = hass.entity("sensor.world_state")
    context += hass.entity("sensor.glitchcube_context")
  end

  def extract_conversation_memories(conversation, logs, context)
    memories = []

    # Extract all conversation text for analysis
    conversation_text = logs.map { |log|
      "#{log.user_message}\n#{log.ai_response}"
    }.join("\n")

    # Extract locations mentioned in conversation
    extracted_locations = extract_locations(conversation_text, context)

    # Extract upcoming events from conversation
    extracted_events = extract_events(conversation_text, conversation.session_id, context)

    # Create conversation memory for significant interactions
    if logs.count >= 3
      event_summary = summarize_interaction(conversation, logs, context, extracted_locations)
      memories << {
        summary: event_summary,
        type: "event",
        importance: calculate_basic_importance(logs),
        metadata: {
          extracted_at: Time.current,
          context: context,
          persona: conversation.persona,
          message_count: logs.count,
          duration: calculate_duration(logs),
          locations: extracted_locations,
          events_mentioned: extracted_events.size
        }
      }
    end

    # Create Event records for upcoming events
    extracted_events.each do |event_data|
      create_event_record(event_data)
    end

    memories
  end

  def extract_preferences(user_messages, ai_responses)
    # Basic implementation - just store that a conversation happened
    # TODO: Implement proper LLM-based memory extraction later
    []
  end

  def has_high_engagement(logs)
    # Consider high engagement if:
    # - Long messages (avg > 50 chars)
    # - Tools were used
    # - Multiple back-and-forth exchanges

    avg_length = logs.map { |log| log.user_message.length }.sum / logs.count.to_f
    has_tools = logs.any? { |log| log.ai_response.include?("[THOUGHTS:") }

    avg_length > 50 || has_tools || logs.count >= 3
  end

  def summarize_interaction(conversation, logs, context, locations = [])
    first_message = logs.first.user_message.truncate(100)
    persona = conversation.persona.capitalize

    summary = "#{context[:time_of_day].capitalize} interaction with #{persona} persona"

    # Add specific locations if mentioned
    if locations.any?
      summary += " discussing #{locations.join(', ')}"
    elsif context[:location] != "Black Rock City"
      summary += " at #{context[:location]}"
    end

    summary += ". Started with: \"#{first_message}\""

    if logs.count >= 5
      summary += ". Extended #{logs.count}-message conversation"
    end

    summary
  end

  def calculate_basic_importance(logs)
    # Simple importance based on conversation length
    case logs.count
    when 3..4 then 5
    when 5..9 then 6
    when 10..20 then 7
    else 8
    end
  end

  def calculate_duration(logs)
    return 0 if logs.count < 2

    start_time = logs.first.created_at
    end_time = logs.last.created_at
    (end_time - start_time).to_i
  end

  def extract_locations(conversation_text, context)
    # Simple keyword-based location extraction
    locations = []

    # Common Burning Man locations
    burning_man_locations = [
      "Center Camp", "Man", "Temple", "Esplanade", "Playa", "Deep Playa",
      "Exodus", "Gate", "Airport", "Rangers", "DMV", "Will Call",
      "Arctica", "Ice", "Trash Fence", "Desert", "Dust Storm"
    ]

    # Check for specific locations mentioned
    burning_man_locations.each do |location|
      if conversation_text.downcase.include?(location.downcase)
        locations << location
      end
    end

    # Extract camp names (simple pattern matching)
    camp_matches = conversation_text.scan(/(?:at|near|by)\s+([A-Z][a-zA-Z\s]+(?:Camp|Village|Plaza))/i)
    locations.concat(camp_matches.flatten.map(&:strip))

    # Extract street addresses (like 6:00 and Esplanade)
    street_matches = conversation_text.scan(/(\d{1,2}:\d{2}(?:\s+and\s+\w+)?)/i)
    locations.concat(street_matches.flatten)

    locations.uniq.take(3) # Limit to avoid noise
  end

  def extract_events(conversation_text, session_id, context)
    events = []

    # Simple pattern matching for events with times
    event_patterns = [
      # "X at location tomorrow at 3pm" or "X tomorrow at 3pm"
      /([^.!?]{10,80}?)\s+(?:tomorrow|today|tonight)\s+at\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm|AM|PM)?)/i,
      # "X happening at Y time"
      /([^.!?]{10,50})\s+(?:happening|starting|beginning)\s+(?:at\s+)?(\d{1,2}(?::\d{2})?\s*(?:am|pm|AM|PM)?)/i,
      # "X is at Y time"
      /([^.!?]{10,50})\s+is\s+at\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm|AM|PM)?)/i,
      # "there is/will be X at time"
      /(?:there\s+(?:is|will\s+be))\s+([^.!?]{10,80}?)\s+at\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm|AM|PM)?)/i
    ]

    event_patterns.each do |pattern|
      conversation_text.scan(pattern) do |match|
        if match.length >= 2
          description = match[0]&.strip
          time_str = match[1]&.strip

          next if description.blank? || time_str.blank?

          # Parse the time (simple approach)
          event_time = parse_event_time(time_str, context)
          next unless event_time

          # Extract location from description if possible
          location = extract_location_from_description(description) || context[:location]

          events << {
            title: generate_event_title(description),
            description: description,
            event_time: event_time,
            location: location,
            importance: 6, # Medium importance for extracted events
            session_id: session_id,
            metadata: {
              extracted_from: "conversation",
              raw_text: "#{description} #{time_str}",
              context: context
            }
          }
        end
      end
    end

    # Remove duplicates by similar titles and same time
    unique_events = []
    events.each do |event|
      unless unique_events.any? { |existing|
        similar_titles?(existing[:title], event[:title]) &&
        (existing[:event_time] - event[:event_time]).abs < 30.minutes
      }
        unique_events << event
      end
    end

    unique_events.take(3) # Limit results
  end

  def parse_event_time(time_str, context)
    return nil if time_str.blank?

    # Simple time parsing - assume today/tomorrow
    base_date = Date.current

    # Parse hour and minute
    if time_str.match(/(\d{1,2})(?::(\d{2}))?\s*(am|pm|AM|PM)?/i)
      hour = $1.to_i
      minute = $2&.to_i || 0
      meridiem = $3&.downcase

      # Convert to 24-hour format
      if meridiem == "pm" && hour != 12
        hour += 12
      elsif meridiem == "am" && hour == 12
        hour = 0
      end

      # If the time has passed today, assume tomorrow
      event_time = base_date.beginning_of_day + hour.hours + minute.minutes
      event_time += 1.day if event_time < Time.current

      event_time
    end
  rescue StandardError
    nil
  end

  def extract_location_from_description(description)
    # Simple location extraction from event description
    return nil if description.blank?

    # Look for "at [location]" pattern, but exclude time words
    if description.match(/\bat\s+([A-Z][a-zA-Z\s]+?)(?:\s+(?:tomorrow|today|tonight|at\s+\d)|\s*$)/i)
      location = $1.strip
      # Remove "tomorrow", "today", etc. if they snuck in
      location.gsub(/\b(?:tomorrow|today|tonight)\b/i, "").strip
    end
  end

  def similar_titles?(title1, title2)
    # Simple similarity check - if one title contains most words of the other
    return false if title1.blank? || title2.blank?

    words1 = title1.downcase.split(/\s+/)
    words2 = title2.downcase.split(/\s+/)

    shorter, longer = [ words1, words2 ].sort_by(&:length)
    common_words = shorter & longer

    # Consider similar if 70% of shorter title words are in longer title
    common_words.length.to_f / shorter.length > 0.7
  end

  def generate_event_title(description)
    # Generate a concise title from description
    return "Untitled Event" if description.blank?

    # Take first few words, clean up
    words = description.split(/\s+/).take(6)
    title = words.join(" ")
    title = title.gsub(/[.!?]+$/, "") # Remove trailing punctuation
    title.length > 50 ? "#{title[0..47]}..." : title
  end

  def create_event_record(event_data)
    return if event_data[:event_time].blank? || event_data[:description].blank?

    # Check if similar event already exists
    existing = Event.where(
      event_time: (event_data[:event_time] - 1.hour)..(event_data[:event_time] + 1.hour),
      title: event_data[:title]
    ).first

    return if existing

    Event.create!(
      title: event_data[:title],
      description: event_data[:description],
      event_time: event_data[:event_time],
      location: event_data[:location],
      importance: event_data[:importance],
      extracted_from_session: event_data[:session_id],
      metadata: event_data[:metadata].to_json
    )

    Rails.logger.info "📅 Created event: #{event_data[:title]} at #{event_data[:event_time]}"
  rescue StandardError => e
    Rails.logger.warn "Failed to create event: #{e.message}"
  end
end
