# frozen_string_literal: true

# Memory::MemoryExtractionService
# Analyzes summaries and extracts future events and key memories for storage
# Called by IntermediateSummarizerJob after creating synthesis summaries
module Memory
  class MemoryExtractionService
    class Error < StandardError; end

    def self.call(summary)
      new(summary).call
    end

    def initialize(summary)
      @summary = summary
      @metadata = summary.metadata_json
    end

    def call
      Rails.logger.info "🧠 Extracting memories and events from summary ID: #{@summary.id}"

      extracted_events = extract_and_create_events
      extracted_memories = extract_and_create_memories

      # Update summary metadata with extraction results
      update_summary_with_extraction_results(extracted_events.count, extracted_memories.count)

      {
        events_created: extracted_events.count,
        memories_created: extracted_memories.count,
        summary_id: @summary.id
      }

    rescue StandardError => e
      Rails.logger.error "❌ Memory extraction failed for summary #{@summary.id}: #{e.message}"
      raise Error, "Failed to extract memories: #{e.message}"
    end

    private

    def extract_and_create_events
      future_events = @metadata["future_events_detected"] || []
      created_events = []

      future_events.each do |event_data|
        next unless event_data.is_a?(Hash) && event_data["description"].present?

        event = create_event_from_detection(event_data)
        created_events << event if event
      end

      Rails.logger.info "📅 Created #{created_events.count} events from summary extraction"
      created_events
    end

    def extract_and_create_memories
      key_memories = @metadata["key_memories_detected"] || []
      created_memories = []

      key_memories.each do |memory_data|
        next unless memory_data.is_a?(Hash) && memory_data["memory"].present?

        memory = create_memory_from_detection(memory_data)
        created_memories << memory if memory
      end

      # Also extract insights from key_insights field as memories
      key_insights = @metadata["key_insights"] || []
      key_insights.each do |insight|
        next unless insight.present?

        memory = create_insight_memory(insight)
        created_memories << memory if memory
      end

      Rails.logger.info "🧠 Created #{created_memories.count} memories from summary extraction"
      created_memories
    end

    def create_event_from_detection(event_data)
      # Parse timeframe into actual datetime
      event_time = parse_event_timeframe(event_data["timeframe"])
      return nil unless event_time

      # Generate a clean title
      title = generate_clean_event_title(event_data["description"])

      # Check if similar event already exists (within 2-hour window)
      existing = Event.where(
        event_time: (event_time - 2.hours)..(event_time + 2.hours)
      ).where("title ILIKE ?", "%#{extract_title_keywords(title)}%").first

      if existing
        Rails.logger.debug "Event already exists: #{title}"
        return nil
      end

      Event.create!(
        title: title,
        description: event_data["description"],
        event_time: event_time,
        location: event_data["location"] || extract_location_from_description(event_data["description"]) || "Black Rock City",
        importance: calculate_event_importance(event_data),
        extracted_from_session: "summary_extraction_#{@summary.id}",
        metadata: {
          extraction_source: "memory_extraction_service",
          confidence: event_data["confidence"],
          original_timeframe: event_data["timeframe"],
          summary_id: @summary.id,
          summary_type: @summary.summary_type,
          extracted_at: Time.current.iso8601
        }.to_json
      )

      Rails.logger.info "📅 Created event: #{title} at #{event_time}"
    rescue StandardError => e
      Rails.logger.warn "Failed to create event from detection: #{e.message}"
      nil
    end

    def create_memory_from_detection(memory_data)
      memory_type = normalize_memory_type(memory_data["type"])
      importance = normalize_importance(memory_data["importance"])

      # Validate memory type
      return nil unless ConversationMemory::MEMORY_TYPES.include?(memory_type)

      # Check for similar memory to avoid duplicates
      existing = ConversationMemory.where(
        "summary ILIKE ?", "%#{memory_data['memory'].truncate(50)}%"
      ).where(memory_type: memory_type).first

      if existing
        Rails.logger.debug "Similar memory already exists: #{memory_data['memory']}"
        return nil
      end

      ConversationMemory.create!(
        session_id: "memory_extraction_#{@summary.id}",
        summary: memory_data["memory"],
        memory_type: memory_type,
        importance: importance,
        metadata: {
          extraction_source: "memory_extraction_service",
          summary_id: @summary.id,
          summary_type: @summary.summary_type,
          original_context: memory_data["context"],
          confidence: memory_data["confidence"],
          extracted_at: Time.current.iso8601
        }.to_json
      )

      Rails.logger.info "🧠 Created memory (#{memory_type}): #{memory_data['memory']}"
    rescue StandardError => e
      Rails.logger.warn "Failed to create memory from detection: #{e.message}"
      nil
    end

    def create_insight_memory(insight)
      # Skip if insight is too short or generic
      return nil if insight.blank? || insight.length < 10 || generic_insight?(insight)

      # Check for similar insight
      existing = ConversationMemory.where(
        "summary ILIKE ?", "%#{insight.truncate(50)}%"
      ).where(memory_type: "context").first

      if existing
        Rails.logger.debug "Similar insight already exists: #{insight}"
        return nil
      end

      ConversationMemory.create!(
        session_id: "insight_extraction_#{@summary.id}",
        summary: "Insight: #{insight}",
        memory_type: "context",
        importance: 6, # Medium importance for insights
        metadata: {
          extraction_source: "insight_extraction",
          summary_id: @summary.id,
          summary_type: @summary.summary_type,
          extracted_at: Time.current.iso8601
        }.to_json
      )

      Rails.logger.info "💡 Created insight memory: #{insight}"
    rescue StandardError => e
      Rails.logger.warn "Failed to create insight memory: #{e.message}"
      nil
    end

    def parse_event_timeframe(timeframe_str)
      return nil unless timeframe_str.present?

      base_time = Time.current

      case timeframe_str.downcase
      when /tonight/
        base_time.end_of_day - 2.hours # 10 PM tonight
      when /tomorrow.*morning/
        (base_time + 1.day).beginning_of_day + 10.hours # 10 AM tomorrow
      when /tomorrow.*afternoon/
        (base_time + 1.day).beginning_of_day + 14.hours # 2 PM tomorrow
      when /tomorrow.*evening/, /tomorrow.*night/
        (base_time + 1.day).beginning_of_day + 20.hours # 8 PM tomorrow
      when /this\s+weekend/
        next_saturday = base_time.next_occurring(:saturday)
        next_saturday.beginning_of_day + 14.hours # 2 PM next Saturday
      when /(sunday.*evening|sunday.*night)/
        next_sunday = base_time.next_occurring(:sunday)
        next_sunday.beginning_of_day + 20.hours # 8 PM next Sunday
      when /(monday.*morning)/
        next_monday = base_time.next_occurring(:monday)
        next_monday.beginning_of_day + 9.hours # 9 AM next Monday
      when /(\d{1,2}):(\d{2})\s*(am|pm)/i
        # Extract specific time
        hour = $1.to_i
        minute = $2.to_i
        meridiem = $3.downcase

        hour += 12 if meridiem == "pm" && hour != 12
        hour = 0 if meridiem == "am" && hour == 12

        event_time = base_time.beginning_of_day + hour.hours + minute.minutes
        event_time += 1.day if event_time < base_time # If time has passed, assume tomorrow

        event_time
      when /next\s+week/
        # Default to next Monday afternoon
        next_monday = base_time.next_occurring(:monday)
        next_monday.beginning_of_day + 14.hours
      when /in\s+(\d+)\s+(hours?|days?)/i
        amount = $1.to_i
        unit = $2.downcase

        if unit.start_with?("hour")
          base_time + amount.hours
        else # days
          base_time + amount.days + 14.hours # Default to afternoon
        end
      else
        # Try to be intelligent about parsing relative time
        if timeframe_str.include?("morning")
          (base_time + 1.day).beginning_of_day + 9.hours
        elsif timeframe_str.include?("afternoon")
          (base_time + 1.day).beginning_of_day + 14.hours
        elsif timeframe_str.include?("evening") || timeframe_str.include?("night")
          (base_time + 1.day).beginning_of_day + 20.hours
        else
          # Default to tomorrow afternoon
          (base_time + 1.day).beginning_of_day + 14.hours
        end
      end
    rescue StandardError => e
      Rails.logger.warn "Failed to parse timeframe '#{timeframe_str}': #{e.message}"
      nil
    end

    def generate_clean_event_title(description)
      return "Extracted Event" if description.blank?

      # Clean up and truncate description for title
      cleaned = description.strip
        .gsub(/^(there is|there will be|there's)\s+/i, "") # Remove leading phrases
        .gsub(/\s+at\s+\d+/, "") # Remove specific times
        .gsub(/\s+(tonight|tomorrow|today)\s+/i, " ") # Remove time references

      # Take first meaningful words
      words = cleaned.split(/\s+/).take(6)
      title = words.join(" ")

      # Clean up punctuation
      title = title.gsub(/[.!?]+$/, "")

      # Capitalize appropriately
      title = title.split(" ").map(&:capitalize).join(" ")

      title.length > 50 ? "#{title[0..47]}..." : title
    end

    def extract_title_keywords(title)
      # Extract key words for similarity matching
      title.downcase.split(/\s+/).reject { |w| w.length < 3 }.take(3).join(" ")
    end

    def extract_location_from_description(description)
      return nil unless description.present?

      # Common Burning Man locations
      locations = [
        "Center Camp", "The Man", "Temple", "Esplanade", "Deep Playa",
        "Trash Fence", "Airport", "Gate", "Rangers", "DMV"
      ]

      locations.each do |location|
        return location if description.include?(location)
      end

      # Extract camp names or street addresses
      if description.match(/\b([A-Z][a-zA-Z\s]+(Camp|Village|Plaza))\b/i)
        return $1.strip
      end

      if description.match(/\b(\d{1,2}:\d{2}(?:\s+and\s+\w+)?)\b/)
        return $1.strip
      end

      nil
    end

    def calculate_event_importance(event_data)
      base_importance = case event_data["confidence"]&.downcase
      when "high" then 8
      when "medium" then 6
      when "low" then 4
      else 5
      end

      # Boost importance for certain keywords
      description = event_data["description"]&.downcase || ""

      if description.include?("burn") || description.include?("temple") || description.include?("man")
        base_importance += 2
      elsif description.include?("party") || description.include?("performance") || description.include?("art")
        base_importance += 1
      end

      [ base_importance, 10 ].min # Cap at 10
    end

    def normalize_memory_type(type_string)
      return "context" unless type_string.present?

      case type_string.downcase
      when "preference", "user_preference"
        "preference"
      when "fact", "information", "knowledge"
        "fact"
      when "instruction", "command", "directive"
        "instruction"
      when "event", "activity", "experience"
        "event"
      when "context", "background", "insight"
        "context"
      else
        "context" # Default fallback
      end
    end

    def normalize_importance(importance_value)
      return 5 unless importance_value.present?

      case importance_value
      when Numeric
        [ [ importance_value.to_i, 1 ].max, 10 ].min
      when String
        case importance_value.downcase
        when "critical", "very high" then 9
        when "high" then 7
        when "medium" then 5
        when "low" then 3
        when "very low" then 1
        else 5
        end
      else
        5
      end
    end

    def generic_insight?(insight)
      generic_patterns = [
        /user (is|was|seems)/i,
        /failed to parse/i,
        /no specific/i,
        /unable to determine/i,
        /unknown/i
      ]

      generic_patterns.any? { |pattern| insight.match?(pattern) }
    end

    def update_summary_with_extraction_results(events_count, memories_count)
      updated_metadata = @metadata.merge(
        "extraction_completed" => true,
        "extraction_results" => {
          "events_created" => events_count,
          "memories_created" => memories_count,
          "extracted_at" => Time.current.iso8601
        }
      )

      @summary.update!(metadata: updated_metadata.to_json)
      Rails.logger.debug "Updated summary #{@summary.id} with extraction results"
    rescue StandardError => e
      Rails.logger.warn "Failed to update summary with extraction results: #{e.message}"
    end
  end
end
