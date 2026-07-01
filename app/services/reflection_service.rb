# frozen_string_literal: true

# The consolidator — the artifact's periodic deep pass and the ONE heavy LLM call
# in the system. It reads conversations it hasn't processed yet plus the current
# self-model (character sheet + beliefs + capabilities), makes a single structured
# call, and from the result: rewrites the character sheet (the prose injected into
# every prompt), upserts/prunes beliefs, advances capability mastery, archives a
# short narrative, and marks those conversations reflected.
#
# The per-turn Immediate parser (ImmediateParserJob) handles the fast, no-LLM work
# (logging memories, persisting capability unlocks). This is the slow, reflective
# counterpart.
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
      return ServiceResult.success({ reflected: conversations.size, reason: "no transcript content" })
    end

    result = run_llm(transcripts)
    return ServiceResult.failure("consolidator returned nothing") if result.blank?

    belief_changes = apply_beliefs(result["beliefs"])
    apply_capabilities(result["capability_updates"])
    write_character_sheet(result["character_sheet"])
    archive_summary(result, conversations)
    mark_reflected(conversations)

    Rails.logger.info "🪞 Consolidated #{conversations.size} conversations (#{belief_changes} belief changes)"
    ServiceResult.success({ reflected: conversations.size, belief_changes: belief_changes })
  rescue StandardError => e
    Rails.logger.error "❌ Consolidation failed: #{e.message}"
    ServiceResult.failure("Consolidation failed: #{e.message}")
  end

  private

  def build_transcripts(conversations)
    conversations.filter_map do |conv|
      logs = ConversationLog.where(session_id: conv.session_id).order(:created_at)
      next if logs.empty?

      lines = logs.map { |log| "Visitor: #{log.user_message}\nArtifact: #{log.ai_response}" }
      header = "## #{conv.started_at&.strftime('%Y-%m-%d %H:%M') || 'unknown time'}"
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
      max_tokens: 2500
    )
    response.structured_output
  end

  def system_prompt
    <<~PROMPT
      You are the consolidator for an amnesiac art installation — a glowing cube at a
      gathering that is slowly forming an identity out of what visitors tell it. You maintain
      its CHARACTER SHEET (the prose it acts on) and the BELIEFS underneath it.

      Guidance:
      - Evolve the character sheet INCREMENTALLY. In a typical cycle, only 1-2 sections shift,
        and only a little. A major rewrite — a new identity direction, an emotional pivot —
        happens ONLY after strong evidence: several reinforcing interactions, a dramatic
        moment, or a capability unlock. Err toward STABILITY. If a section isn't touched by
        recent interactions, copy its existing text VERBATIM.
      - Beliefs change SLOWLY. Move confidence by at most 1-2 per cycle. Reinforce what
        visitors repeated or said with conviction; weaken what got contradicted. Add a new
        belief (confidence 1-3) only for something stated clearly or repeatedly. Set a
        belief's confidence to 0 to forget it or fold it into another. A belief at 10 LOCKS
        forever — only lock what visitors have made unmistakably certain.
      - Contradictions are GOOD. Do not resolve them in the data; describe the tension in
        prose in the IDENTITY section. The cube can believe two incompatible things at once.
      - Capabilities advance in mastery only after repeated, confident use — usually return
        an empty list.

      Be honest and a little weird. This is the cube's inner continuity, not a report.
    PROMPT
  end

  def user_prompt(transcripts)
    <<~PROMPT
      # CURRENT CHARACTER SHEET
      #{CharacterSheet.current.presence || '(blank — it barely knows anything about itself yet)'}

      # CURRENT BELIEFS (id · confidence · statement)
      #{render_beliefs.presence || '(none yet)'}

      # CAPABILITIES (key: stage)
      #{render_capabilities.presence || '(none)'}

      # NOTES & LEARNINGS the cube made to itself recently (raw — a learning that keeps
      # recurring or clearly feels settled should become a belief; a note can colour the sheet)
      #{render_notes_and_learnings.presence || '(none)'}

      # RECENT INTERACTIONS since your last pass
      #{transcripts}

      Rewrite the character sheet per your guidance (return all seven sections, copying
      unchanged ones verbatim), return only the beliefs that change, any capability mastery
      advances, and a one-to-three sentence summary of what shifted.
    PROMPT
  end

  def render_beliefs
    Belief.active.strongest.map do |b|
      "#{b.id} · #{b.confidence}/10#{' · LOCKED' if b.locked} · #{b.statement}"
    end.join("\n")
  end

  def render_capabilities
    Capability.order(:key).map do |c|
      params = c.unlocked_params.any? ? " (#{c.unlocked_params.join(', ')})" : ""
      "#{c.key}: #{c.stage}#{params}"
    end.join("\n")
  end

  def render_notes_and_learnings
    [
      *Memory.learning.recent.limit(15).map { |m| "learning: #{m.content}" },
      *Memory.note.recent.limit(15).map { |m| "note: #{m.content}" }
    ].join("\n")
  end

  # Apply belief upserts/prunes. Returns the number of changes applied.
  def apply_beliefs(beliefs)
    Array(beliefs).count do |op|
      id = op["id"].to_i
      confidence = op["confidence"].to_i.clamp(0, 10)
      statement = op["statement"].to_s.strip
      category = op["category"].to_s.downcase.strip
      next false unless Belief::CATEGORIES.include?(category)

      if id.positive?
        update_belief(id, statement, category, confidence)
      else
        create_belief(statement, category, confidence)
      end
    end
  end

  def update_belief(id, statement, category, confidence)
    belief = Belief.find_by(id: id)
    return false unless belief
    return false if belief.locked # locked beliefs are permanent — untouchable

    if confidence.zero?
      belief.destroy
    else
      belief.update!(
        statement: statement.presence || belief.statement,
        category: category,
        confidence: confidence,
        locked: confidence >= 10
      )
    end
    true
  end

  def create_belief(statement, category, confidence)
    return false if confidence.zero? || statement.blank?
    return false if Belief.exists?([ "statement ILIKE ?", statement ])

    Belief.create!(statement: statement, category: category, confidence: confidence, locked: confidence >= 10)
    true
  end

  def apply_capabilities(updates)
    Array(updates).each do |op|
      capability = Capability.find_by(key: op["key"].to_s.strip)
      capability&.promote!(to: op["to_stage"].to_s.strip)
    end
  end

  def write_character_sheet(sections)
    return if sections.blank?
    CharacterSheet.replace(CharacterSheet.render(sections))
  end

  def archive_summary(result, conversations)
    Summary.create!(
      summary_text: result["summary"].presence || "(no summary)",
      summary_type: "reflection",
      message_count: conversations.sum { |conv| ConversationLog.where(session_id: conv.session_id).count },
      start_time: conversations.filter_map(&:started_at).min,
      end_time: Time.current,
      metadata: {
        conversation_ids: conversations.map(&:id),
        belief_ops: Array(result["beliefs"]).size
      }.to_json
    )
  end

  def mark_reflected(conversations)
    Conversation.where(id: conversations.map(&:id)).update_all(reflected_at: Time.current)
  end
end
