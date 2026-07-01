# frozen_string_literal: true

# A single thing the artifact believes about itself or the world. Beliefs are
# backstage raw material — they are NOT injected into the prompt directly. The
# consolidator reads them as a set and writes the character sheet (the prose the
# model actually sees). Confidence drifts: reinforced up by conversations, decayed
# down overnight by the amnesia loop, locked permanently at 10.
class Belief < ApplicationRecord
  CATEGORIES = %w[self world].freeze
  CONFIDENCE_RANGE = (0..10).freeze

  validates :statement, presence: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :confidence, presence: true, inclusion: { in: CONFIDENCE_RANGE }

  scope :self_beliefs, -> { where(category: "self") }
  scope :world_beliefs, -> { where(category: "world") }
  scope :active, -> { where(confidence: 1..) }
  scope :locked, -> { where(locked: true) }
  scope :strongest, -> { order(confidence: :desc, updated_at: :desc) }

  # Nudge confidence up; a belief that reaches 10 locks forever.
  def reinforce!(amount = 1)
    self.confidence = [ confidence + amount, 10 ].min
    self.locked = true if confidence >= 10
    save!
  end

  # Nudge confidence down (decay/contradiction). Locked beliefs are immune.
  def weaken!(amount = 1)
    return if locked
    update!(confidence: [ confidence - amount, 0 ].max)
  end

  def lock!
    update!(locked: true, confidence: 10)
  end
end
