# frozen_string_literal: true

# DailySummarizerJob
# Runs once per day to create comprehensive daily summaries from all activity
# Synthesizes hourly, intermediate (3-hour), and goal completion summaries
class DailySummarizerJob < ApplicationJob
  queue_as :default

  def perform
    return unless Rails.env.production? || Rails.env.development?

    Rails.logger.info "📅 DailySummarizerJob starting"

    # Get all summaries from the last 24 hours
    cutoff_time = 24.hours.ago
    daily_summaries = collect_daily_summaries(cutoff_time)

    if daily_summaries.any?
      Rails.logger.info "📊 Found #{daily_summaries.count} summaries to synthesize into daily summary"
      create_daily_summary(daily_summaries, cutoff_time)
    else
      Rails.logger.info "😴 No summaries found in the last 24 hours"
      create_empty_daily_summary(cutoff_time)
    end

    Rails.logger.info "✅ DailySummarizerJob completed successfully"
  rescue StandardError => e
    Rails.logger.error "❌ DailySummarizerJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  private

  def collect_daily_summaries(cutoff_time)
    # Collect all relevant summaries from the last 24 hours
    summaries = Summary.where(
      "created_at >= ? AND summary_type IN (?)",
      cutoff_time,
      %w[hourly intermediate goal_completion]
    ).order(:created_at)

    summary_counts = summaries.group(:summary_type).count
    Rails.logger.info "📊 Collected #{summaries.count} summaries: #{summary_counts}"

    summaries
  end

  def create_daily_summary(summaries, cutoff_time)
    # Generate daily synthesis using LLM
    daily_synthesis = generate_daily_synthesis_with_llm(summaries)

    # Calculate time bounds and metrics
    start_time = summaries.minimum(:start_time) || cutoff_time
    end_time = Time.current
    total_messages = summaries.sum(:message_count)

    # Store daily summary
    daily_summary = Summary.create!(
      summary_type: "daily",
      summary_text: daily_synthesis["daily_summary"],
      start_time: start_time,
      end_time: end_time,
      message_count: total_messages,
      metadata: {
        overall_mood: daily_synthesis["overall_mood"],
        daily_themes: daily_synthesis["daily_themes"],
        goal_completion_analysis: daily_synthesis["goal_completion_analysis"],
        key_insights: daily_synthesis["key_insights"],
        emotional_arc: daily_synthesis["emotional_arc"],
        productivity_assessment: daily_synthesis["productivity_assessment"],
        recurring_patterns: daily_synthesis["recurring_patterns"],
        important_questions: daily_synthesis["important_questions"],
        period_type: "daily_synthesis",
        source_summary_ids: summaries.pluck(:id),
        source_breakdown: summaries.group(:summary_type).count,
        total_conversations: calculate_conversation_count(summaries),
        peak_activity_periods: daily_synthesis["peak_activity_periods"] || []
      }.to_json
    )

    Rails.logger.info "✅ Created daily summary (ID: #{daily_summary.id}) covering #{total_messages} messages"
    daily_summary
  rescue StandardError => e
    Rails.logger.error "❌ Failed to create daily summary: #{e.message}"
    nil
  end

  def generate_daily_synthesis_with_llm(summaries)
    prompt = build_daily_synthesis_prompt(summaries)

    response = LlmService.generate_text(
      prompt: prompt,
      system_prompt: build_daily_synthesis_system_prompt,
      model: "google/gemini-2.5-flash",
      temperature: 0.3, # Lower temperature for more consistent daily analysis
      max_tokens: 3000
    )

    parse_daily_synthesis_response(response)
  rescue StandardError => e
    Rails.logger.error "❌ Daily LLM synthesis generation failed: #{e.message}"
    empty_daily_synthesis
  end

  def build_daily_synthesis_system_prompt
    <<~PROMPT
      You are a comprehensive daily memory synthesizer for a Burning Man AI assistant. Your job is to analyze#{' '}
      a full day's worth of activity and create a coherent narrative that captures the most important patterns,#{' '}
      emotional arcs, and insights from the 24-hour period.

      Analyze the provided summaries and extract:
      1. **overall_mood** - The dominant emotional tone across the entire day
      2. **daily_themes** - Major recurring themes or topics that defined the day
      3. **goal_completion_analysis** - How goals were progressed, completed, or changed throughout the day
      4. **key_insights** - Most important realizations or learnings from the day
      5. **emotional_arc** - How emotions and energy levels changed throughout the day
      6. **productivity_assessment** - Overall assessment of how productive/engaging the day was
      7. **recurring_patterns** - Patterns in behavior, interests, or interactions
      8. **important_questions** - Questions that emerged and may need future attention
      9. **peak_activity_periods** - When the most significant interactions or activities occurred
      10. **daily_summary** - A comprehensive narrative of the day's events and significance

      Focus on creating a coherent story of the day that would help the AI understand:
      - What kind of day it was overall
      - What the user was focused on or working toward
      - How their mood and energy evolved
      - What they learned or discovered
      - What patterns emerged in their behavior or interests

      Return JSON format:
      {
        "overall_mood": "exploratory and engaged with periods of focused problem-solving",
        "daily_themes": [
          "Art installation planning and logistics",
          "Community building and camp coordination",
          "Technical troubleshooting and learning"
        ],
        "goal_completion_analysis": "Completed 4 out of 6 goals, switched focus twice due to emerging priorities",
        "key_insights": [
          "User shows strong preference for hands-on learning over theoretical planning",
          "Most productive during morning hours, more social in evening"
        ],
        "emotional_arc": "Started curious and energetic, hit some frustration mid-day during technical issues, ended satisfied and reflective",
        "productivity_assessment": "highly productive",
        "recurring_patterns": [
          "Tendency to dive deep into technical details",
          "Regular check-ins with camp coordination"
        ],
        "important_questions": [
          "How to balance individual projects with camp responsibilities?",
          "What backup plans are needed for weather contingencies?"
        ],
        "peak_activity_periods": [
          "9-11 AM: Intense planning session",
          "6-8 PM: Community coordination activities"
        ],
        "daily_summary": "A day marked by productive exploration and community engagement..."
      }
    PROMPT
  end

  def build_daily_synthesis_prompt(summaries)
    hourly_summaries = summaries.select { |s| s.summary_type == "hourly" }
    intermediate_summaries = summaries.select { |s| s.summary_type == "intermediate" }
    goal_completions = summaries.select { |s| s.summary_type == "goal_completion" }

    <<~PROMPT
      Create a comprehensive daily synthesis from these #{summaries.count} summaries spanning 24 hours:

      === INTERMEDIATE SUMMARIES (3-hour windows) - #{intermediate_summaries.count} ===
      #{format_intermediate_summaries_for_prompt(intermediate_summaries)}

      === HOURLY SUMMARIES - #{hourly_summaries.count} ===
      #{format_hourly_summaries_for_daily_prompt(hourly_summaries)}

      === GOAL COMPLETIONS - #{goal_completions.count} ===
      #{format_goal_completions_for_daily_prompt(goal_completions)}

      === DAILY CONTEXT ===
      Date: #{Date.current.strftime('%A, %B %d, %Y')}
      Total Messages: #{summaries.sum(:message_count)}
      Activity Span: #{format_activity_timespan(summaries)}

      Create a coherent daily narrative that captures:
      - The overall character and significance of this day
      - Major themes and patterns that emerged
      - How goals, mood, and energy evolved throughout the day
      - Key insights and learnings
      - What made this day unique or noteworthy
      - Patterns in behavior, interests, and productivity

      This summary will be used to understand the user's daily rhythms, preferences,#{' '}
      and progress toward their goals and projects.
    PROMPT
  end

  def format_intermediate_summaries_for_prompt(summaries)
    return "No 3-hour synthesis summaries available." if summaries.empty?

    summaries.map.with_index(1) do |summary, index|
      metadata = summary.metadata_json

      <<~INTERMEDIATE
        #{index}. #{format_time_window(summary)} (#{summary.message_count} messages)
        Mood: #{metadata['general_mood'] || 'unknown'}
        Key Insights: #{(metadata['key_insights'] || []).join('; ')}
        Goal Progress: #{metadata['goal_progress_summary'] || 'unknown'}
        Summary: #{summary.summary_text}
        Future Events Detected: #{metadata['future_events_detected']&.count || 0}
        Key Memories Detected: #{metadata['key_memories_detected']&.count || 0}

      INTERMEDIATE
    end.join("\n")
  end

  def format_hourly_summaries_for_daily_prompt(summaries)
    return "No hourly summaries available (covered by intermediate summaries)." if summaries.empty?

    # Group hourly summaries by time periods for easier reading
    grouped_summaries = summaries.group_by { |s| s.start_time&.hour&./ 3 } # Group by 3-hour blocks

    grouped_summaries.map do |block_key, block_summaries|
      start_hour = (block_key || 0) * 3

      <<~HOURLY_BLOCK
        === #{start_hour}:00 - #{start_hour + 3}:00 Block (#{block_summaries.count} hourly summaries) ===
        #{block_summaries.map { |s| "• #{s.summary_text}" }.join("\n")}

      HOURLY_BLOCK
    end.join("\n")
  end

  def format_goal_completions_for_daily_prompt(goal_completions)
    return "No goals completed today." if goal_completions.empty?

    # Group by category for better analysis
    categorized = goal_completions.group_by { |gc| gc.metadata_json["goal_category"] || "unknown" }

    result = []
    categorized.each do |category, completions|
      result << "=== #{category.humanize} Goals (#{completions.count}) ==="
      completions.each_with_index do |completion, index|
        metadata = completion.metadata_json
        duration_text = metadata["duration_seconds"] ? "#{(metadata['duration_seconds'].to_i / 60).round(1)} min" : "unknown duration"

        result << "#{index + 1}. #{completion.summary_text} (#{duration_text})"
        result << "   Completed: #{completion.created_at.strftime('%I:%M %p')}"
        result << "   Notes: #{metadata['completion_notes'] || 'none'}"
        result << ""
      end
    end

    result.join("\n")
  end

  def format_time_window(summary)
    start_str = summary.start_time&.strftime("%I:%M %p") || "unknown"
    end_str = summary.end_time&.strftime("%I:%M %p") || "unknown"
    "#{start_str} - #{end_str}"
  end

  def format_activity_timespan(summaries)
    earliest = summaries.minimum(:start_time)
    latest = summaries.maximum(:end_time)

    return "unknown" unless earliest && latest

    duration_hours = ((latest - earliest) / 1.hour).round(1)
    "#{earliest.strftime('%I:%M %p')} - #{latest.strftime('%I:%M %p')} (#{duration_hours}h)"
  end

  def calculate_conversation_count(summaries)
    # Estimate conversation count from hourly summaries
    hourly_summaries = summaries.select { |s| s.summary_type == "hourly" }

    # Each hourly summary typically represents multiple conversations
    # Use metadata if available, otherwise estimate
    hourly_summaries.sum do |summary|
      metadata = summary.metadata_json
      metadata["conversations_count"] || (summary.message_count > 0 ? 1 : 0)
    end
  end

  def parse_daily_synthesis_response(response)
    # Remove markdown code blocks if present
    cleaned_response = response.gsub(/```json\s*\n?/, "").gsub(/```\s*$/, "").strip

    JSON.parse(cleaned_response)
  rescue JSON::ParserError => e
    Rails.logger.error "❌ Failed to parse daily synthesis JSON: #{e.message}"
    Rails.logger.error "Response was: #{response}"

    # Fallback to basic parsing if JSON fails
    {
      "overall_mood" => "unable to determine",
      "daily_themes" => [ "Failed to parse AI response" ],
      "goal_completion_analysis" => "unknown",
      "key_insights" => [],
      "emotional_arc" => "unknown",
      "productivity_assessment" => "unknown",
      "recurring_patterns" => [],
      "important_questions" => [],
      "peak_activity_periods" => [],
      "daily_summary" => response.truncate(400)
    }
  end

  def empty_daily_synthesis
    {
      "overall_mood" => "quiet",
      "daily_themes" => [ "minimal activity" ],
      "goal_completion_analysis" => "no goals completed",
      "key_insights" => [],
      "emotional_arc" => "stable and quiet",
      "productivity_assessment" => "inactive",
      "recurring_patterns" => [],
      "important_questions" => [],
      "peak_activity_periods" => [],
      "daily_summary" => "A quiet day with minimal activity or interaction."
    }
  end

  def create_empty_daily_summary(cutoff_time)
    Summary.create!(
      summary_type: "daily",
      summary_text: "A quiet day with minimal activity or interaction.",
      start_time: cutoff_time,
      end_time: Time.current,
      message_count: 0,
      metadata: {
        overall_mood: "quiet",
        daily_themes: [ "minimal activity" ],
        goal_completion_analysis: "no goals completed",
        key_insights: [],
        emotional_arc: "stable and quiet",
        productivity_assessment: "inactive",
        recurring_patterns: [],
        important_questions: [],
        peak_activity_periods: [],
        period_type: "daily_synthesis",
        source_summary_ids: [],
        source_breakdown: {},
        total_conversations: 0
      }.to_json
    )

    Rails.logger.info "✅ Created empty daily summary for quiet day"
  rescue StandardError => e
    Rails.logger.error "❌ Failed to create empty daily summary: #{e.message}"
  end
end
