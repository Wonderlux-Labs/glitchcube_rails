# frozen_string_literal: true

# A physical thing the cube can do. Starts `latent` — sensed but unreachable —
# and is unlocked when a visitor teaches the underlying concept. Gates nothing in
# code: it only informs the prompt (the artifact attempts only what it knows it
# can do). The artifact names each ability in its own emergent `vocabulary`.
class Capability < ApplicationRecord
  STAGES = %w[latent discovered partial mastered].freeze

  validates :key, presence: true, uniqueness: true
  validates :stage, presence: true, inclusion: { in: STAGES }

  scope :unlocked, -> { where.not(stage: "latent") }
  scope :still_latent, -> { where(stage: "latent") }

  def unlocked?
    stage != "latent"
  end

  # Advance to the next stage, or to a named target — never downgrade.
  def promote!(to: nil)
    target = to.presence || STAGES[STAGES.index(stage) + 1]
    return unless target && STAGES.index(target)
    return unless STAGES.index(target) > STAGES.index(stage)
    update!(stage: target)
  end

  # Reveal a new sub-parameter (e.g. "color" on the light) the visitor just taught.
  def unlock_param!(param)
    param = param.to_s
    return if param.blank? || unlocked_params.include?(param)
    update!(unlocked_params: unlocked_params + [ param ])
  end

  # Merge in new artifact-vocabulary entries (add-only; never wipes existing words,
  # only overwrites a word that's explicitly re-defined).
  def merge_vocabulary!(additions)
    additions = additions.to_h.transform_keys(&:to_s).reject { |k, v| k.blank? || v.to_s.blank? }
    return if additions.empty?
    update!(vocabulary: vocabulary.merge(additions))
  end
end
