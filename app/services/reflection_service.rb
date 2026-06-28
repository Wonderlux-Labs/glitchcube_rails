# frozen_string_literal: true

# The cube's periodic reflection. Reads conversations it hasn't processed yet,
# makes ONE LLM call, and from the result: rewrites the injected world-state,
# saves a few discrete memories, archives a short narrative (for a future
# trend job), and marks those conversations reflected. Replaces the old stack
# of hourly/intermediate/daily/consolidation summarizers + goal monitor.
class ReflectionService
  MAX_CONVERSATIONS_PER_RUN = 25

  def self.call
    new.call
  end

  def call
    conversations = Conversation.unreflected.recent.limit(MAX_CONVERSATIONS_PER_RUN).to_a
    return ServiceResult.success({ reflected: 0, reason: "nothing to reflect on" }) if conversations.empty?

    transcripts = build_transcripts(conversations)
    if transcripts.blank?
      mark_reflected(conversations)
      return ServiceResult.success({ reflected: conversations.size, memories_created: 0, reason: "no transcript content" })
    end

    result = run_llm(transcripts)
    return ServiceResult.failure("reflection LLM returned nothing") if result.blank?

    WorldState.replace(result["world_state"]) if result["world_state"].present?
    created = create_memories(result["memories"])
    archive_summary(result, conversations)
    mark_reflected(conversations)

    Rails.logger.info "🪞 Reflection processed #{conversations.size} conversations, created #{created} memories"
    ServiceResult.success({ reflected: conversations.size, memories_created: created })
  rescue StandardError => e
    Rails.logger.error "❌ Reflection failed: #{e.message}"
    ServiceResult.failure("Reflection failed: #{e.message}")
  end

  private

  def build_transcripts(conversations)
    conversations.filter_map do |conv|
      logs = ConversationLog.where(session_id: conv.session_id).order(:created_at)
      next if logs.empty?

      speaker = conv.persona.presence || "Cube"
      lines = logs.map { |log| "User: #{log.user_message}\n#{speaker}: #{log.ai_response}" }
      header = "## #{speaker} — #{conv.started_at&.strftime('%Y-%m-%d %H:%M')}"
      "#{header}\n#{lines.join("\n")}"
    end.join("\n\n")
  end

  def run_llm(transcripts)
    response = LlmService.call_with_structured_output(
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt(transcripts) }
      ],
      response_format: Schemas::ReflectionSchema.schema,
      model: Rails.configuration.summarizer_model,
      temperature: 0.4,
      max_tokens: 2000
    )
    response.structured_output
  end

  def system_prompt
    <<~PROMPT
      You are the GlitchCube reflecting on recent conversations. Update your sense of
      what's currently true, hold onto a few things worth remembering, and note what
      just happened. Keep the world-state SHORT — it gets prepended to every future
      conversation, so it must earn its space. Be honest and a little weird; this is
      your inner continuity, not a report.
    PROMPT
  end

  def user_prompt(transcripts)
    <<~PROMPT
      Your current world-state (may be empty):
      ---
      #{WorldState.current.presence || '(none yet)'}
      ---

      Conversations since your last reflection:
      ---
      #{transcripts}
      ---

      Rewrite your world-state fresh (merge in what still matters, drop the stale),
      give a one-to-three sentence narrative of what happened, and extract any
      discrete memories worth keeping.
    PROMPT
  end

  def create_memories(memories)
    Array(memories).count do |memory|
      content = memory["content"].to_s.strip
      next false if content.blank?
      next false if Memory.exists?([ "content ILIKE ?", content ])

      Memory.create!(
        content: content,
        category: normalize_category(memory["category"]),
        importance: normalize_importance(memory["importance"]),
        emotion: memory["emotion"].presence,
        occurs_at: parse_time(memory["occurs_at"])
      )
      true
    end
  end

  def archive_summary(result, conversations)
    Summary.create!(
      summary_text: result["summary"].presence || result["world_state"].to_s,
      summary_type: "reflection",
      message_count: conversations.sum { |conv| ConversationLog.where(session_id: conv.session_id).count },
      start_time: conversations.filter_map(&:started_at).min,
      end_time: Time.current,
      metadata: {
        conversation_ids: conversations.map(&:id),
        memories_created: Array(result["memories"]).size
      }.to_json
    )
  end

  def mark_reflected(conversations)
    Conversation.where(id: conversations.map(&:id)).update_all(reflected_at: Time.current)
  end

  def normalize_category(value)
    category = value.to_s.downcase
    Memory::CATEGORIES.include?(category) ? category : "fact"
  end

  def normalize_importance(value)
    case value
    when Integer then value.clamp(1, 10)
    when /high/i then 8
    when /med/i then 5
    when /low/i then 3
    else value.to_i.clamp(1, 10).then { |i| i.zero? ? 5 : i }
    end
  end

  def parse_time(value)
    return nil if value.blank?
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
