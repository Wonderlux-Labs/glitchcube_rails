# frozen_string_literal: true

# Deep-recall over the Memory table. Plain Rails search — no embeddings.
#
# Standalone service kept for a future background memory consolidator / deep-recall
# path (not currently wired into the persona turn). Answers things like
# "do I have a memory of a storm?" (keyword) or "any events happening tomorrow?"
# (category + timeframe).
#
# Extracted from the retired in-Rails tool stack (was Tools::Query::MemorySearch).
# The environment/tool-calling machinery now lives on the Home Assistant agent
# (see EnvironmentDirectorJob); this is the one query-side piece we kept.
class MemorySearchService
  def self.call(**args)
    new.call(**args)
  end

  def call(query: nil, category: nil, timeframe: nil, limit: 5, **_args)
    if query.blank? && category.blank? && timeframe.blank?
      return error_response("Provide at least one of query, category, or timeframe")
    end

    window = time_window(timeframe)
    memories = Memory.search(
      query: query,
      category: category,
      on_or_after: window[:from],
      on_or_before: window[:to],
      limit: limit.to_i.clamp(1, 10)
    )

    results = memories.map do |memory|
      {
        content: memory.content,
        category: memory.category,
        importance: memory.importance,
        emotion: memory.emotion,
        occurs_at: memory.occurs_at&.iso8601
      }
    end

    success_response(
      results.empty? ? "No memories found" : "Found #{results.size} memories",
      { results: results, total_results: results.size }
    )
  rescue StandardError => e
    Rails.logger.error "Memory search error: #{e.message}"
    error_response("Search failed: #{e.message}")
  end

  private

  def time_window(timeframe)
    case timeframe.to_s.downcase
    when "upcoming" then { from: Time.current, to: nil }
    when "today"    then { from: Time.current.beginning_of_day, to: Time.current.end_of_day }
    when "tomorrow" then { from: 1.day.from_now.beginning_of_day, to: 1.day.from_now.end_of_day }
    else { from: nil, to: nil }
    end
  end

  def success_response(message, data = {})
    { success: true, message: message, **data }
  end

  def error_response(message, details = {})
    { success: false, error: message, **details }
  end
end
