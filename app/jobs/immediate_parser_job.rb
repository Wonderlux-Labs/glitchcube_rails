# frozen_string_literal: true

# The Immediate parser — the fast, per-turn pass. Runs async after every turn with
# NO extra LLM call (cellular-friendly). It does the time-sensitive, no-reasoning
# work so the next turn reflects it:
#
#   1. Persist a capability unlock the brain declared this turn (and remember the
#      discovery as a milestone).
#   2. Record a deliberate note-to-self, IF the brain asked to remember something.
#   3. Record a significant learning, IF the brain realized something new about
#      itself or the world.
#
# Most turns produce none of these — memory is intentional, not mechanical. All the
# slow, reflective work (beliefs, the character sheet) belongs to the consolidator.
class ImmediateParserJob < ApplicationJob
  queue_as :default

  def perform(session_id:, user_message: nil, newly_realized_capability: nil, memory_note: nil, significant_learning: nil)
    capability = persist_capability_unlock(newly_realized_capability)
    record_discovery(capability, session_id) if capability
    record_note(memory_note, user_message, session_id) if memory_note.present?
    record_learning(significant_learning, session_id) if significant_learning.present?
  end

  private

  # Promote a latent capability to `discovered`, reveal a sub-param, and record the
  # artifact's own name/vocabulary for it. Returns the capability if newly unlocked.
  def persist_capability_unlock(payload)
    payload = normalize(payload)
    key = payload["key"].to_s.strip
    return nil if key.blank?

    capability = Capability.find_by(key: key)
    return nil unless capability

    was_latent = capability.stage == "latent"
    capability.promote!(to: "discovered") if was_latent
    capability.unlock_param!(payload["param"]) if payload["param"].present?
    capability.update!(artifact_name: payload["artifact_name"]) if payload["artifact_name"].present?
    if payload["vocabulary_word"].present?
      capability.merge_vocabulary!(payload["vocabulary_word"] => payload["vocabulary_meaning"])
    end

    Rails.logger.info "✨ Capability unlocked/advanced: #{capability.key} → #{capability.stage}"
    capability
  end

  # A discovery is a milestone — always worth remembering, even if the brain didn't
  # also flag it as a learning.
  def record_discovery(capability, session_id)
    label = capability.artifact_name.presence || capability.key
    create_memory("I discovered a new ability: #{label}.", category: "learning", importance: 8,
                  metadata: { session_id: session_id, capability_unlocked: capability.key })
  end

  # The cube's deliberate note to itself — only when it chose to remember something.
  # Importance 7 so it survives the daily prune (deliberate memories persist).
  def record_note(text, user_message, session_id)
    create_memory(text.to_s.strip, category: "note", importance: 7,
                  metadata: { session_id: session_id, visitor_said: user_message.to_s.strip.presence })
  end

  # A fresh, not-yet-settled realization about itself or the world. Surfaced back as
  # working knowledge until the consolidator promotes it to a belief — or, if it
  # never sticks, it fades in a day (importance 6 < the prune threshold).
  def record_learning(text, session_id)
    create_memory(text.to_s.strip, category: "learning", importance: 6,
                  metadata: { session_id: session_id })
  end

  def create_memory(content, category:, importance:, metadata:)
    return if content.blank?
    Memory.create!(content: content, category: category, importance: importance, metadata: metadata.compact.to_json)
  rescue StandardError => e
    Rails.logger.warn "⚠️ ImmediateParser failed to create #{category} memory: #{e.message}"
  end

  def normalize(payload)
    return {} if payload.blank?
    payload.respond_to?(:to_h) ? payload.to_h.transform_keys(&:to_s) : {}
  end
end
