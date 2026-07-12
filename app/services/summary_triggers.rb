# frozen_string_literal: true

# Decides what summarization work to enqueue after a conversation turn is recorded.
# Called from ConversationOrchestrator::Finalizer once per turn. The only trigger here is
# the interaction CHUNK: every ~N turns of a persona's stint we enqueue a factual chunk.
# There is deliberately NO mid-stint persona fold — the persona summarizer runs only on
# switch (wired in PersonaSwitchService), which avoids over-steering a still-active persona.
class SummaryTriggers
  CHUNK_EVERY = 8 # interaction-chunk cadence, kept in step with the raw-history window (8)

  def self.after_turn(persona_slug)
    new(persona_slug).after_turn
  end

  def initialize(persona_slug)
    @slug = persona_slug.to_s
  end

  def after_turn
    persona = Persona[@slug]
    return unless persona

    turns = unsummarized_turns(persona)
    return unless turns.positive? && (turns % CHUNK_EVERY).zero?

    Recurring::Memory::SummarizerJob.perform_later(@slug)
  rescue => e
    # Never let a summarization trigger break the conversation turn.
    Rails.logger.warn "⚠️ SummaryTriggers(#{@slug}) failed: #{e.message}"
  end

  private

  # Turns for this persona since its last interaction chunk — clamped to the persona-fold
  # boundary (same cursor as SummarizerService#logs_since), so already-folded turns never
  # count toward the next chunk.
  def unsummarized_turns(persona)
    last_chunk_end = Summary.interaction.where(persona_id: persona.id).recent.first&.end_time
    since = [ last_chunk_end, Summary.fold_boundary_for(persona) ].compact.max
    scope = ConversationLog.joins(:conversation).where(conversations: { persona: persona.slug })
    scope = scope.where("conversation_logs.created_at > ?", since) if since
    scope.count
  end
end
