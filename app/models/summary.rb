# frozen_string_literal: true

class Summary < ApplicationRecord
  vectorsearch

  after_save :upsert_to_vectorsearch

  SUMMARY_TYPES = %w[hourly daily intermediate session topic goal_completion consolidated].freeze

  validates :summary_text, presence: true
  validates :summary_type, presence: true, inclusion: { in: SUMMARY_TYPES }
  validates :message_count, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :by_type, ->(type) { where(summary_type: type) }
  scope :recent, -> { order(created_at: :desc) }
  scope :chronological, -> { order(start_time: :asc) }

  # Dynamic scopes for all summary types
  SUMMARY_TYPES.each do |type|
    scope type.to_sym, -> { where(summary_type: type) }
  end

  def metadata_json
    return {} if metadata.blank?
    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end


  def metadata_json=(hash)
    self.metadata = hash.to_json
  end

  def duration
    return nil unless start_time && end_time
    end_time - start_time
  end

  def duration_in_minutes
    return nil unless duration
    (duration / 60).round(2)
  end

  # Convenience scope for goal completions
  def self.goal_completions
    where(summary_type: "goal_completion")
  end

  # Get all completed goals with formatted data
  def self.completed_goals
    goal_completions.recent.map do |summary|
      metadata = summary.metadata_json
      {
        goal_id: metadata["goal_id"],
        goal_category: metadata["goal_category"],
        description: summary.summary_text,
        completed_at: summary.created_at,
        duration: metadata["duration_seconds"],
        completion_notes: metadata["completion_notes"],
        expired: metadata["expired"]
      }
    end
  end

  def self.get_themes
    ask("What are the main themes and topics that have emerged across conversations?")
  end

  def self.get_current_events
    ask("What are any major current events, news, or important happenings we need to be aware about?")
  end

  def self.text_search_fallback(question, limit: 10)
    # Simple text-based search as fallback
    keywords = question.downcase.split(/\W+/).reject(&:blank?)

    # Search in summary text and metadata
    scope = where("summary_type != 'consolidated'") # Prefer non-consolidated summaries

    # Create search conditions for each keyword
    search_conditions = keywords.map do |keyword|
      "summary_text ILIKE ? OR metadata ILIKE ?"
    end.join(" OR ")

    search_values = keywords.flat_map { |keyword| [ "%#{keyword}%", "%#{keyword}%" ] }

    scope.where(search_conditions, *search_values)
         .order(created_at: :desc)
         .limit(limit)
  end

  private

  def self.build_rag_context(results, question)
    context_parts = []

    results.first(8).each_with_index do |summary, idx|
      metadata = summary.metadata_json

      context_parts << <<~CONTEXT
        === Summary #{idx + 1} (#{summary.summary_type}) ===
        Time: #{summary.start_time&.strftime('%Y-%m-%d %H:%M')} - #{summary.end_time&.strftime('%Y-%m-%d %H:%M')}
        Content: #{summary.summary_text}
        Questions: #{Array(metadata['important_questions']).join('; ')}
        Thoughts: #{Array(metadata['useful_thoughts']).join('; ')}
        Topics: #{Array(metadata['topics']).join(', ')}
        Mood: #{metadata['general_mood']}
      CONTEXT
    end

    context_parts.join("\n\n")
  end

  def self.synthesize_answer(question, context)
    prompt = <<~PROMPT
      Based on the following conversation summaries, answer this question: #{question}

      #{context}

      Provide a comprehensive answer that synthesizes insights from the summaries. Be specific and reference patterns or examples from the data. If the summaries don't contain relevant information, say so clearly.
    PROMPT

    begin
      response = LlmService.generate_text(
        prompt: prompt,
        system_prompt: "You are analyzing conversation summaries to answer questions about user interactions and patterns.",
        model: Rails.configuration.summarizer_model,
        temperature: 0.1,
        max_tokens: 1500
      )

      response.strip
    rescue StandardError => e
      Rails.logger.error "❌ Failed to synthesize Summary answer: #{e.message}"
      "Error: Unable to analyze summaries - #{e.message}"
    end
  end

  # Content for vector search includes summary text and metadata
  def vectorsearch_fields_content
    content_parts = [ summary_text ]

    metadata = metadata_json
    content_parts << "mood: #{metadata['general_mood']}" if metadata["general_mood"].present?
    content_parts << "topics: #{Array(metadata['topics']).join(', ')}" if metadata["topics"]&.any?
    content_parts << "questions: #{Array(metadata['important_questions']).join('; ')}" if metadata["important_questions"]&.any?
    content_parts << "insights: #{Array(metadata['useful_thoughts']).join('; ')}" if metadata["useful_thoughts"]&.any?

    content_parts.join(" ")
  end

  private

  def vectorsearch_fields
    {
      content: vectorsearch_fields_content
    }
  end
end
