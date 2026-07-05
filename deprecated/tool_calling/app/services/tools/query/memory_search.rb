# frozen_string_literal: true

# Deep-recall tool. Plain Rails search over the Memory table — no embeddings.
# Kept for a future background memory consolidator (not wired into the persona
# turn). Answers things like "do I have a memory of a storm?" (keyword) or "any
# events happening tomorrow?" (category + timeframe).
class Tools::Query::MemorySearch < Tools::BaseTool
  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "memory_search"
      description "Search the cube's saved memories by keyword, category, and timeframe"

      parameters do
        string :query, description: "Keyword to match against memory content"
        string :category, description: "Limit to one category", enum: Memory::CATEGORIES
        string :timeframe, description: "Time filter for event memories", enum: %w[upcoming today tomorrow]
        integer :limit, description: "Max results, 1-10 (default 5)"
      end
    end
  end

  def self.description
    "Search saved memories by keyword, category, and timeframe (no semantic search)"
  end

  def self.prompt_schema
    "memory_search(query: 'storm', category: 'event', timeframe: 'tomorrow', limit: 5)"
  end

  def self.tool_type
    :sync
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
end
