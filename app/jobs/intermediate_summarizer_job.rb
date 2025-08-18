# frozen_string_literal: true

# IntermediateSummarizerJob
# Runs every 3 hours to create higher-level summaries of hourly summaries and goal completions
# Creates 'intermediate' type summaries and extracts future events and key memories
class IntermediateSummarizerJob < ApplicationJob
  queue_as :default

  def perform
    return unless Rails.env.production? || Rails.env.development?

    Rails.logger.info "🧠 IntermediateSummarizerJob starting"

    # Get all summaries from the last 3 hours
    cutoff_time = 3.hours.ago
    recent_summaries = collect_recent_summaries(cutoff_time)

    if recent_summaries.any?
      Rails.logger.info "📊 Found #{recent_summaries.count} summaries to synthesize into intermediate summary"
      intermediate_summary = create_intermediate_summary(recent_summaries, cutoff_time)

      # Extract future events and key memories from the intermediate summary
      extract_memories_and_events_with_service(intermediate_summary) if intermediate_summary
    else
      Rails.logger.info "😴 No summaries found in the last 3 hours"
      create_empty_intermediate_summary(cutoff_time)
    end

    Rails.logger.info "✅ IntermediateSummarizerJob completed successfully"
  rescue StandardError => e
    Rails.logger.error "❌ IntermediateSummarizerJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  private

  def collect_recent_summaries(cutoff_time)
    # Collect hourly summaries and goal completions from the last 3 hours
    summaries = Summary.where(
      "created_at >= ? AND summary_type IN (?)",
      cutoff_time,
      %w[hourly goal_completion]
    ).order(:created_at)

    Rails.logger.info "📊 Collected #{summaries.count} summaries: #{summaries.group(:summary_type).count}"
    summaries
  end

  def create_intermediate_summary(summaries, cutoff_time)
    # Generate synthesis using LLM
    synthesis_data = generate_synthesis_with_llm(summaries)

    # Calculate time bounds
    start_time = summaries.minimum(:start_time) || cutoff_time
    end_time = Time.current
    total_messages = summaries.sum(:message_count)

    # Store intermediate summary
    intermediate_summary = Summary.create!(
      summary_type: "intermediate",
      summary_text: synthesis_data["synthesis_summary"],
      start_time: start_time,
      end_time: end_time,
      message_count: total_messages,
      metadata: {
        general_mood: synthesis_data["general_mood"],
        key_insights: synthesis_data["key_insights"],
        important_questions: synthesis_data["important_questions"],
        goal_progress_summary: synthesis_data["goal_progress_summary"],
        future_events_detected: synthesis_data["future_events_detected"] || [],
        key_memories_detected: synthesis_data["key_memories_detected"] || [],
        period_type: "3_hour_synthesis",
        source_summary_ids: summaries.pluck(:id),
        source_summary_count: summaries.count,
        is_intermediate: true
      }.to_json
    )

    Rails.logger.info "✅ Created intermediate summary (ID: #{intermediate_summary.id})"
    intermediate_summary
  rescue StandardError => e
    Rails.logger.error "❌ Failed to create intermediate summary: #{e.message}"
    nil
  end

  def generate_synthesis_with_llm(summaries)
    prompt = build_synthesis_prompt(summaries)

    response = LlmService.generate_text(
      prompt: prompt,
      system_prompt: build_synthesis_system_prompt,
      model: "google/gemini-2.5-flash",
      temperature: 0.4,
      max_tokens: 2000
    )

    parse_synthesis_response(response)
  rescue StandardError => e
    Rails.logger.error "❌ LLM synthesis generation failed: #{e.message}"
    empty_synthesis
  end

  def build_synthesis_system_prompt
    <<~PROMPT
      You are a high-level memory synthesizer for a Burning Man AI assistant. Your job is to analyze multiple#{' '}
      time periods and create a coherent 3-hour synthesis that captures the most important patterns and insights.

      Analyze the provided summaries and extract:
      1. **general_mood** - Overall emotional arc across the 3-hour period
      2. **key_insights** - Most important realizations, patterns, or learnings
      3. **important_questions** - Questions that need follow-up or show recurring themes
      4. **goal_progress_summary** - How goals progressed or changed during this period
      5. **future_events_detected** - Any events or activities mentioned for the future
      6. **key_memories_detected** - Important facts, preferences, or context that should be remembered
      7. **synthesis_summary** - A comprehensive narrative of what happened in this 3-hour window

      Focus on identifying:
      - Recurring themes and patterns
      - Emotional progressions
      - Goal completion and switching patterns
      - Future planning and event mentions
      - Important personal preferences or facts revealed

      Return JSON format:
      {
        "general_mood": "productive and exploratory",
        "key_insights": [
          "User is planning their first burn experience",
          "Strong pattern of technical problem-solving emerged"
        ],
        "important_questions": [
          "How do the art cars coordinate their routes?",
          "What's the best way to find specific camps?"
        ],
        "goal_progress_summary": "Completed 2 exploration goals, switched to preparation mode",
        "future_events_detected": [
          {
            "description": "Temple burn ceremony Sunday night",
            "confidence": "high",
            "timeframe": "Sunday evening"
          }
        ],
        "key_memories_detected": [
          {
            "memory": "User prefers interactive art over passive viewing",
            "type": "preference",
            "importance": 7
          }
        ],
        "synthesis_summary": "3-hour period marked by active exploration and preparation..."
      }
    PROMPT
  end

  def build_synthesis_prompt(summaries)
    goal_completions = summaries.select { |s| s.summary_type == "goal_completion" }
    hourly_summaries = summaries.select { |s| s.summary_type == "hourly" }

    <<~PROMPT
      Synthesize the following #{summaries.count} summaries from a 3-hour period:

      === HOURLY SUMMARIES (#{hourly_summaries.count}) ===
      #{format_hourly_summaries_for_prompt(hourly_summaries)}

      === GOAL COMPLETIONS (#{goal_completions.count}) ===
      #{format_goal_completions_for_prompt(goal_completions)}

      Current Context:
      #{build_current_context}

      Create a coherent synthesis that identifies patterns, emotional arcs, recurring themes,
      and important insights from this 3-hour window. Focus on what's most significant
      for understanding the user's experience and planning future interactions.

      Pay special attention to:
      - Any future events mentioned that should be tracked
      - Personal preferences or facts that should be remembered
      - Goal progression patterns
      - Emotional or mood changes
      - Recurring questions or interests
    PROMPT
  end

  def format_hourly_summaries_for_prompt(summaries)
    return "No hourly summaries in this period." if summaries.empty?

    summaries.map.with_index(1) do |summary, index|
      metadata = summary.metadata_json

      <<~SUMMARY
        #{index}. #{summary.start_time&.strftime('%I:%M %p')} - #{summary.end_time&.strftime('%I:%M %p')}
        Mood: #{metadata['general_mood'] || 'unknown'}
        Messages: #{summary.message_count}
        Summary: #{summary.summary_text}
        Questions: #{(metadata['important_questions'] || []).join('; ')}
        Thoughts: #{(metadata['useful_thoughts'] || []).join('; ')}
        Goal Progress: #{metadata['goal_progress'] || 'unknown'}

      SUMMARY
    end.join("\n")
  end

  def format_goal_completions_for_prompt(goal_completions)
    return "No goals completed in this period." if goal_completions.empty?

    goal_completions.map.with_index(1) do |completion, index|
      metadata = completion.metadata_json

      <<~COMPLETION
        #{index}. Goal: #{completion.summary_text}
        Category: #{metadata['goal_category'] || 'unknown'}
        Duration: #{metadata['duration_seconds']&.to_i&./(60)&.round(1) || 'unknown'} minutes
        Completed: #{completion.created_at.strftime('%I:%M %p')}
        Notes: #{metadata['completion_notes'] || 'none'}
        Expired?: #{metadata['expired'] ? 'yes' : 'no'}

      COMPLETION
    end.join("\n")
  end

  def build_current_context
    begin
      goal_status = GoalService.current_goal_status
      current_goal = goal_status ? goal_status[:goal_description] : "No active goal"
      safety_mode = GoalService.safety_mode_active? ? "SAFETY MODE ACTIVE" : "Normal operation"

      "Current Goal: #{current_goal} | #{safety_mode} | Time: #{Time.current.strftime('%A %I:%M %p')}"
    rescue StandardError => e
      Rails.logger.error "Failed to build current context: #{e.message}"
      "Context unavailable"
    end
  end

  def parse_synthesis_response(response)
    # Remove markdown code blocks if present
    cleaned_response = response.gsub(/```json\s*\n?/, "").gsub(/```\s*$/, "").strip

    JSON.parse(cleaned_response)
  rescue JSON::ParserError => e
    Rails.logger.error "❌ Failed to parse synthesis JSON: #{e.message}"
    Rails.logger.error "Response was: #{response}"

    # Fallback to basic parsing if JSON fails
    {
      "general_mood" => "unable to determine",
      "key_insights" => [ "Failed to parse AI response" ],
      "important_questions" => [],
      "goal_progress_summary" => "unknown",
      "future_events_detected" => [],
      "key_memories_detected" => [],
      "synthesis_summary" => response.truncate(300)
    }
  end

  def empty_synthesis
    {
      "general_mood" => "quiet",
      "key_insights" => [],
      "important_questions" => [],
      "goal_progress_summary" => "no activity",
      "future_events_detected" => [],
      "key_memories_detected" => [],
      "synthesis_summary" => "Quiet 3-hour period with no significant activity."
    }
  end

  def create_empty_intermediate_summary(cutoff_time)
    Summary.create!(
      summary_type: "intermediate",
      summary_text: "Quiet 3-hour period with no significant activity.",
      start_time: cutoff_time,
      end_time: Time.current,
      message_count: 0,
      metadata: {
        general_mood: "quiet",
        key_insights: [],
        important_questions: [],
        goal_progress_summary: "no activity",
        future_events_detected: [],
        key_memories_detected: [],
        period_type: "3_hour_synthesis",
        source_summary_ids: [],
        source_summary_count: 0,
        is_intermediate: true
      }.to_json
    )

    Rails.logger.info "✅ Created empty intermediate summary for quiet period"
  rescue StandardError => e
    Rails.logger.error "❌ Failed to create empty intermediate summary: #{e.message}"
  end

  def extract_memories_and_events_with_service(intermediate_summary)
    # Use the dedicated MemoryExtractionService for consistent extraction
    extraction_results = Memory::MemoryExtractionService.call(intermediate_summary)

    Rails.logger.info "🧠 MemoryExtractionService results: #{extraction_results[:events_created]} events, #{extraction_results[:memories_created]} memories"
  rescue StandardError => e
    Rails.logger.error "❌ Failed to extract memories and events with service: #{e.message}"
  end

  def create_event_from_synthesis(event_data, summary_id)
    return unless event_data.is_a?(Hash) && event_data["description"].present?

    # Parse timeframe into actual datetime if possible
    event_time = parse_event_timeframe(event_data["timeframe"])
    return unless event_time

    # Check if similar event already exists
    existing = Event.where(
      event_time: (event_time - 2.hours)..(event_time + 2.hours),
      title: generate_event_title(event_data["description"])
    ).first

    return if existing

    Event.create!(
      title: generate_event_title(event_data["description"]),
      description: event_data["description"],
      event_time: event_time,
      location: event_data["location"] || "Black Rock City",
      importance: calculate_event_importance(event_data["confidence"]),
      extracted_from_session: "intermediate_summary_#{summary_id}",
      metadata: {
        extraction_source: "intermediate_synthesis",
        confidence: event_data["confidence"],
        original_timeframe: event_data["timeframe"],
        summary_id: summary_id
      }.to_json
    )

    Rails.logger.info "📅 Created event from synthesis: #{event_data['description']}"
  rescue StandardError => e
    Rails.logger.warn "Failed to create event from synthesis: #{e.message}"
  end

  def create_memory_from_synthesis(memory_data, summary_id)
    return unless memory_data.is_a?(Hash) && memory_data["memory"].present?

    memory_type = memory_data["type"] || "context"
    importance = memory_data["importance"] || 5

    # Validate memory type
    return unless ConversationMemory::MEMORY_TYPES.include?(memory_type)

    ConversationMemory.create!(
      session_id: "intermediate_synthesis_#{summary_id}",
      summary: memory_data["memory"],
      memory_type: memory_type,
      importance: [ importance.to_i, 10 ].min, # Cap at 10
      metadata: {
        extraction_source: "intermediate_synthesis",
        summary_id: summary_id,
        original_context: memory_data["context"]
      }.to_json
    )

    Rails.logger.info "🧠 Created memory from synthesis: #{memory_data['memory']}"
  rescue StandardError => e
    Rails.logger.warn "Failed to create memory from synthesis: #{e.message}"
  end

  def parse_event_timeframe(timeframe_str)
    return nil unless timeframe_str.present?

    # Simple parsing for common patterns
    base_time = Time.current

    case timeframe_str.downcase
    when /tonight/
      base_time.end_of_day - 2.hours # 10 PM tonight
    when /tomorrow.*morning/
      (base_time + 1.day).beginning_of_day + 10.hours # 10 AM tomorrow
    when /tomorrow.*evening/, /tomorrow.*night/
      (base_time + 1.day).beginning_of_day + 20.hours # 8 PM tomorrow
    when /sunday.*evening/, /sunday.*night/
      next_sunday = base_time.next_occurring(:sunday)
      next_sunday.beginning_of_day + 20.hours # 8 PM next Sunday
    when /(\d{1,2}):(\d{2})\s*(am|pm)/
      # Extract time and assume today or tomorrow
      hour = $1.to_i
      minute = $2.to_i
      meridiem = $3.downcase

      hour += 12 if meridiem == "pm" && hour != 12
      hour = 0 if meridiem == "am" && hour == 12

      event_time = base_time.beginning_of_day + hour.hours + minute.minutes
      event_time += 1.day if event_time < base_time # If time has passed, assume tomorrow

      event_time
    else
      # Default to tomorrow evening if can't parse
      (base_time + 1.day).beginning_of_day + 20.hours
    end
  rescue StandardError
    nil
  end

  def generate_event_title(description)
    # Generate a concise title from description
    return "Extracted Event" if description.blank?

    # Take first few words, clean up
    words = description.split(/\s+/).take(5)
    title = words.join(" ")
    title = title.gsub(/[.!?]+$/, "") # Remove trailing punctuation
    title.length > 40 ? "#{title[0..37]}..." : title
  end

  def calculate_event_importance(confidence)
    case confidence&.downcase
    when "high" then 8
    when "medium" then 6
    when "low" then 4
    else 5
    end
  end
end
