# frozen_string_literal: true

# Runs the memory searches the brain requested and stores results in
# conversation.metadata_json["pending_query_results"] for injection next turn.
# Async so deep recall never blocks the spoken response — same speak-first,
# act-async policy as EnvironmentDirectorJob.
class MemorySearchJob < ApplicationJob
  queue_as :default

  def perform(conversation_id:, searches:)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    limit = Rails.configuration.memory_search_limit
    results = {}

    Array(searches).each_with_index do |search, index|
      search = search.symbolize_keys if search.respond_to?(:symbolize_keys)
      query = search[:query]
      next if query.blank? && search[:category].blank? && search[:timeframe].blank?

      begin
        result = Tools::Registry.execute_tool(
          "memory_search",
          query: query,
          category: search[:category],
          timeframe: search[:timeframe],
          limit: limit
        )
        results["memory_search_#{index + 1}"] = result
        Rails.logger.info "🧠 Async memory search: #{query} — #{result[:total_results] || 0} results"
      rescue => e
        Rails.logger.error "❌ Async memory search failed: #{query} — #{e.message}"
        results["memory_search_#{index + 1}"] = { success: false, error: e.message, query: query }
      end
    end

    return if results.empty?

    summary = results.map do |key, result|
      if result[:success] == false
        "#{key}: search failed — #{result[:error]}"
      else
        hits = Array(result[:results]).map { |memory| memory[:content] }.join("; ")
        "#{key} (#{result[:total_results]} results): #{hits}"
      end
    end.join("\n")

    metadata = (conversation.metadata_json || {}).merge(
      "pending_query_results" => {
        "results_summary" => summary,
        "tool_count"      => results.size,
        "completed_at"    => Time.current.iso8601
      }
    )
    conversation.update!(metadata_json: metadata)
    Rails.logger.info "🔍 Stored #{results.size} memory search results for conversation #{conversation_id}"
  end
end
