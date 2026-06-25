# app/jobs/memory_store_job.rb
#
# Persists facts the brain LLM flagged worth remembering (the `memories` field
# of NarrativeResponseSchema). Runs async so the embedding write
# (ConversationMemory#upsert_to_vectorsearch) never blocks the spoken response —
# same speak-first, act-async policy as EnvironmentDirectorJob.
class MemoryStoreJob < ApplicationJob
  queue_as :default

  ALLOWED_TYPES = ConversationMemory::MEMORY_TYPES

  def perform(session_id:, memories:)
    Array(memories).each do |memory|
      summary = (memory["summary"] || memory[:summary]).to_s.strip
      next if summary.blank?

      ConversationMemory.create!(
        session_id: session_id,
        summary: summary,
        memory_type: normalize_type(memory["memory_type"] || memory[:memory_type]),
        importance: normalize_importance(memory["importance"] || memory[:importance]),
        metadata: { "source" => "conversation" }.to_json
      )
      Rails.logger.info "🧠 Stored memory for #{session_id}: #{summary}"
    end
  end

  private

  # LLM output is untrusted — clamp it into the model's valid ranges rather than
  # letting a stray value raise mid-turn.
  def normalize_type(type)
    ALLOWED_TYPES.include?(type) ? type : "fact"
  end

  def normalize_importance(importance)
    (importance || 5).to_i.clamp(ConversationMemory::IMPORTANCE_RANGE.min, ConversationMemory::IMPORTANCE_RANGE.max)
  end
end
