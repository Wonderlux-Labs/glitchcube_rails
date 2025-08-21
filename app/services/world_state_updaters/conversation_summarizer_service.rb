# app/services/world_state_updaters/conversation_summarizer_service.rb

class WorldStateUpdaters::ConversationSummarizerService
  class Error < StandardError; end

  def self.call(conversation_ids)
    new(conversation_ids).call
  end

  def initialize(conversation_ids)
    @conversation_ids = Array(conversation_ids)
  end

  def call
    Rails.logger.info "🧠 Starting conversation summarizer for #{@conversation_ids.count} conversations"

    conversation_data = gather_conversation_data
    return create_empty_summary if conversation_data.empty?

    summary_data = generate_summary_with_llm(conversation_data)
    summary_record = store_summary(summary_data, conversation_data)

    Rails.logger.info "✅ Conversation summary completed successfully"
    summary_record
  rescue StandardError => e
    Rails.logger.error "❌ Conversation summary failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise Error, "Failed to generate conversation summary: #{e.message}"
  end

  private

  def gather_conversation_data
    conversations = Conversation.includes(:conversation_logs)
                               .where(id: @conversation_ids)

    conversation_data = conversations.map do |conversation|
      logs = conversation.conversation_logs.chronological

      # Extract mood, thoughts, and questions from each log
      self_awareness_data = []
      questions_data = []
      people_data = []
      events_data = []

      logs.each do |log|
        # Try to extract structured data first, then fall back to text analysis
        extracted = extract_structured_data(log) || extract_from_text(log)

        self_awareness_data.concat(extracted[:self_awareness]) if extracted[:self_awareness]&.any?
        thoughts_data.concat(extracted[:thoughts]) if extracted[:thoughts]&.any?
        questions_data.concat(extracted[:questions]) if extracted[:questions]&.any?
        events_data.concat(extracted[:events]) if extracted[:events]&.any?
      end

      {
        session_id: conversation.session_id,
        persona: conversation.persona,
        started_at: conversation.started_at,
        ended_at: conversation.ended_at,
        duration: conversation.duration,
        total_exchanges: logs.count,

        # Core conversation content
        conversation_logs: logs.map do |log|
          {
            user_message: log.user_message,
            ai_response: log.ai_response,
            timestamp: log.created_at
          }
        end,

        # Extracted elements
        mood_progression: mood_data,
        inner_thoughts: thoughts_data,
        questions: questions_data
      }
    end.compact

    Rails.logger.info "📊 Gathered data from #{conversation_data.count} conversations"
    conversation_data
  end

  def extract_structured_data(log)
    # Try to parse structured JSON-like data from AI responses
    response = log.ai_response

    # Look for JSON blocks or structured data patterns
    if response.include?("current_mood") || response.include?("inner_thoughts") || response.include?("questions")
      # Try to extract structured data
      mood = extract_field(response, "current_mood")
      thoughts = extract_array_field(response, "inner_thoughts")
      questions = extract_array_field(response, "questions")

      return {
        mood: mood,
        thoughts: thoughts,
        questions: questions
      }
    end

    nil
  end

  def extract_from_text(log)
    # Extract emotional and thought content from unstructured text
    response = log.ai_response
    user_message = log.user_message

    {
      mood: infer_mood_from_text(response),
      thoughts: extract_insights_from_text(response, user_message),
      questions: extract_questions_from_text(response)
    }
  end

  def extract_field(text, field_name)
    # Simple regex to extract structured field values
    pattern = /#{field_name}["']?\s*:\s*["']?([^",\n}]+)["']?/i
    match = text.match(pattern)
    match&.captures&.first&.strip
  end

  def extract_array_field(text, field_name)
    # Extract array-like fields
    pattern = /#{field_name}["']?\s*:\s*\[([^\]]+)\]/i
    match = text.match(pattern)
    return [] unless match

    array_content = match.captures.first
    # Split by comma and clean up
    array_content.split(",").map { |item| item.strip.gsub(/["']/, "") }
  end

  def infer_mood_from_text(text)
    # Simple mood inference based on text patterns
    text_lower = text.downcase

    case text_lower
    when /fuck yeah|awesome|amazing|excited|stoked|pumped/
      "excited"
    when /frustrated|annoyed|pissed|damn|shit|error|failed/
      "frustrated"
    when /confused|don't understand|what.*\?|unclear/
      "confused"
    when /helping|assist|support|here for you/
      "helpful"
    when /chill|relaxed|calm|peaceful/
      "calm"
    else
      "neutral"
    end
  end

  def extract_insights_from_text(response, user_message)
    insights = []

    # Look for thought patterns in responses
    if response.include?("I think") || response.include?("seems like") || response.include?("probably")
      insights << "Analytical thinking about: #{user_message.truncate(50)}"
    end

    if response.include?("remember") || response.include?("earlier") || response.include?("before")
      insights << "Referencing previous context or memory"
    end

    if response.match?(/let me|I'll|going to/)
      insights << "Taking action or planning next steps"
    end

    insights
  end

  def extract_questions_from_text(text)
    # Extract actual questions from the text
    questions = text.scan(/[^.!]*\?[^.!]*/)
                   .map(&:strip)
                   .reject(&:empty?)
                   .map { |q| q.sub(/^.*?([A-Z])/, '\1') } # Clean up question starts

    questions.first(3) # Limit to 3 most important questions
  end

  def generate_summary_with_llm(conversation_data)
    prompt = build_summary_prompt(conversation_data)

    response = LlmService.generate_text(
      prompt: prompt,
      system_prompt: build_system_prompt,
      model: "google/gemini-2.5-flash",
      temperature: 0.4,
      max_tokens: 1500
    )

    parse_summary_response(response)
  rescue StandardError => e
    Rails.logger.error "❌ LLM summary generation failed: #{e.message}"
    empty_summary
  end

  def build_system_prompt
    <<~PROMPT
      You are a conversation summarizer for a Burning Man AI assistant. Analyze conversations and extract key insights.

      Create a comprehensive summary with these elements:
      1. **important_questions** - Key questions that were asked or need follow-up
      2. **useful_thoughts** - Valuable insights, realizations, or patterns observed
      3. **goal_progress** - Did the persona make progress toward or complete their current goal? (completed, good_progress, some_progress, no_progress, goal_changed)
      4. **people to remember** - Concise overview of what happened in this time period
      5  **events past or present** - Events must have a description and and address and a d
      Return JSON format:
      {
        "general_mood": "excited and helpful",
        "important_questions": [
          "How do I find the best art installations?",
          "What time does the Temple burn?"
        ],
        "useful_thoughts": [
          "User is planning their first Burning Man experience",
          "Strong interest in fire performances and art"
        ],
        "goal_progress": "good_progress",
        "general_summary": "Active planning session for Burning Man activities, focusing on art and performances. User showed high engagement and excitement."
      }

      Focus on actionable insights and emotional patterns. Keep it concise but meaningful.
    PROMPT
  end

  def build_summary_prompt(conversation_data)
    total_exchanges = conversation_data.sum { |c| c[:total_exchanges] }
    time_span = calculate_time_span(conversation_data)

    <<~PROMPT
      Analyze and summarize these #{conversation_data.length} conversations from the last #{time_span}:

      Total exchanges: #{total_exchanges}

      #{format_conversations_for_prompt(conversation_data)}

      Current Goal Context:
      #{build_goal_context_for_prompt}

      Create a summary that captures the essence of this time period - what was the overall mood,#{' '}
      what important questions came up, what insights were gained, what progress was made toward goals,#{' '}
      and what happened overall.
    PROMPT
  end

  def calculate_time_span(conversation_data)
    return "unknown period" if conversation_data.empty?

    start_time = conversation_data.map { |c| c[:started_at] }.compact.min
    end_time = conversation_data.map { |c| c[:ended_at] }.compact.max

    return "unknown period" unless start_time && end_time

    duration = (end_time - start_time) / 1.hour
    "#{duration.round(1)} hours"
  end

  def format_conversations_for_prompt(conversation_data)
    conversation_data.map do |conv|
      mood_summary = conv[:mood_progression].any? ?
        "Mood progression: #{conv[:mood_progression].join(' → ')}" :
        "Mood: neutral"

      thoughts_summary = conv[:inner_thoughts].any? ?
        "Key thoughts: #{conv[:inner_thoughts].first(3).join('; ')}" :
        "No specific thoughts captured"

      questions_summary = conv[:questions].any? ?
        "Questions: #{conv[:questions].join('; ')}" :
        "No questions asked"

      <<~CONV
        === Conversation #{conv[:session_id]} (#{conv[:persona]}) ===
        Duration: #{conv[:duration]&.round(1)}s | Exchanges: #{conv[:total_exchanges]}
        #{mood_summary}
        #{thoughts_summary}
        #{questions_summary}

        Sample exchanges:
        #{format_sample_exchanges(conv[:conversation_logs])}

      CONV
    end.join("\n")
  end

  def format_sample_exchanges(logs)
    # Show first, middle, and last exchange to give good context
    sample_logs = case logs.length
    when 0..2
                    logs
    when 3..6
                    [ logs.first, logs.last ]
    else
                    [ logs.first, logs[logs.length / 2], logs.last ]
    end

    sample_logs.map do |log|
      "User: #{log[:user_message].truncate(100)}\nAI: #{log[:ai_response].truncate(150)}\n"
    end.join("\n")
  end

  def parse_summary_response(response)
    # Remove markdown code blocks if present
    cleaned_response = response.gsub(/```json\s*\n?/, "").gsub(/```\s*$/, "").strip

    JSON.parse(cleaned_response)
  rescue JSON::ParserError => e
    Rails.logger.error "❌ Failed to parse summary JSON: #{e.message}"
    Rails.logger.error "Response was: #{response}"

    # Fallback to basic parsing if JSON fails
    {
      "general_mood" => "unable to determine",
      "important_questions" => [],
      "useful_thoughts" => [ "Failed to parse AI response" ],
      "general_summary" => response.truncate(200)
    }
  end

  def store_summary(summary_data, conversation_data)
    # Calculate time bounds from conversation data
    start_time = conversation_data.map { |c| c[:started_at] }.compact.min
    end_time = conversation_data.map { |c| c[:ended_at] }.compact.max
    total_exchanges = conversation_data.sum { |c| c[:total_exchanges] }

    # Store in Summary model with hourly type
    Summary.create!(
      summary_type: "hourly",
      summary_text: summary_data["general_summary"],
      start_time: start_time,
      end_time: end_time,
      message_count: total_exchanges,
      metadata: {
        general_mood: summary_data["general_mood"],
        important_questions: summary_data["important_questions"],
        useful_thoughts: summary_data["useful_thoughts"],
        goal_progress: summary_data["goal_progress"],
        conversation_ids: @conversation_ids,
        conversations_count: conversation_data.length
      }.to_json
    )
  end

  def create_empty_summary
    Summary.create!(
      summary_type: "hourly",
      summary_text: "No conversations found in this time period.",
      start_time: 30.minutes.ago,
      end_time: Time.current,
      message_count: 0,
      metadata: {
        general_mood: "quiet",
        important_questions: [],
        useful_thoughts: [],
        goal_progress: "no_progress",
        conversation_ids: @conversation_ids,
        conversations_count: 0
      }.to_json
    )
  end

  def build_goal_context_for_prompt
    begin
      goal_status = GoalService.current_goal_status
      return "No active goal" unless goal_status

      safety_mode = GoalService.safety_mode_active?
      context_parts = []

      if safety_mode
        context_parts << "SAFETY MODE ACTIVE"
      end

      context_parts << "Active Goal: #{goal_status[:goal_description]}"
      context_parts << "Goal Category: #{goal_status[:category]}"

      if goal_status[:time_remaining] && goal_status[:time_remaining] > 0
        context_parts << "Time Remaining: #{(goal_status[:time_remaining] / 60).to_i} minutes"
      elsif goal_status[:expired]
        context_parts << "Goal Status: EXPIRED"
      end

      context_parts.join(", ")
    rescue StandardError => e
      Rails.logger.error "Failed to build goal context for prompt: #{e.message}"
      "Goal context unavailable"
    end
  end

  def empty_summary
    {
      "general_mood" => "quiet",
      "important_questions" => [],
      "useful_thoughts" => [],
      "goal_progress" => "no_progress",
      "general_summary" => "No conversations found in this time period."
    }
  end
end
