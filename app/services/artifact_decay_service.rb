# frozen_string_literal: true

# The amnesia loop — pure arithmetic, NO LLM. Once a day the artifact wakes dimmer:
# every non-locked belief loses a little confidence (its sense of SELF fades faster
# than facts about the WORLD), and any belief that reaches 0 is forgotten. The day's
# conversations restore what still matters, so identity firms up by afternoon and
# fades again overnight. Also prunes the mundane interaction log so the memory table
# doesn't grow unbounded — significant memories (discoveries) survive.
class ArtifactDecayService
  SELF_DECAY = 2
  WORLD_DECAY = 1
  MEMORY_TTL = 24.hours
  SIGNIFICANT_IMPORTANCE = 7

  def self.call
    new.call
  end

  def call
    decayed = decay_beliefs
    forgotten = forget_dead_beliefs
    pruned = prune_memories

    Rails.logger.info "🌫️ Amnesia loop: #{decayed} beliefs decayed, #{forgotten} forgotten, #{pruned} memories pruned"
    ServiceResult.success({ decayed: decayed, forgotten: forgotten, pruned: pruned })
  rescue StandardError => e
    Rails.logger.error "❌ Decay failed: #{e.message}"
    ServiceResult.failure("Decay failed: #{e.message}")
  end

  private

  def decay_beliefs
    count = 0
    Belief.where(locked: false).where("confidence > 0").find_each do |belief|
      amount = belief.category == "self" ? SELF_DECAY : WORLD_DECAY
      belief.update!(confidence: [ belief.confidence - amount, 0 ].max)
      count += 1
    end
    count
  end

  def forget_dead_beliefs
    Belief.where(locked: false, confidence: 0).delete_all
  end

  def prune_memories
    Memory.where("importance < ? AND created_at < ?", SIGNIFICANT_IMPORTANCE, MEMORY_TTL.ago).delete_all
  end
end
