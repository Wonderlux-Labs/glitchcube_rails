# app/jobs/memory_search_job.rb
#
# Runs RAG memory searches requested by the brain LLM and stores results in
# conversation.metadata_json["pending_query_results"] for injection next turn.
# Async so the embedding call never blocks the spoken response — same
# speak-first, act-async policy as EnvironmentDirectorJob and MemoryStoreJob.
class MemorySearchJob < ApplicationJob
  queue_as :default

  def perform(conversation_id:, searches:)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    limit = Rails.configuration.memory_search_limit
    results = {}

    Array(searches).each_with_index do |search_request, index|
      query = search_request["query"] || search_request[:query]
      type  = search_request["type"]  || search_request[:type]  || "all"
      next if query.blank?

      begin
        result = Tools::Registry.execute_tool("rag_search", query: query, type: type, limit: limit)
        results["memory_search_#{index + 1}"] = result
        Rails.logger.info "🧠 Async memory search: #{query} (#{type}) — #{result[:total_results] || 0} results"
      rescue => e
        Rails.logger.error "❌ Async memory search failed: #{query} — #{e.message}"
        results["memory_search_#{index + 1}"] = { success: false, error: e.message, query: query }
      end
    end

    return if results.empty?

    summary = results.map do |key, r|
      if r[:success] == false
        "#{key}: search failed — #{r[:error]}"
      else
        hits = Array(r[:results]).map { |m| m[:summary] }.join("; ")
        "#{key} (#{r[:total_results]} results): #{hits}"
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
