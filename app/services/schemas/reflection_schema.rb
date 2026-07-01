# frozen_string_literal: true

# Structured output for the consolidator — the periodic deep pass, the ONE heavy
# LLM call. It reads recent memories, the current belief set, the current
# character sheet, and capabilities, then returns a rewritten character sheet
# (the prose the artifact acts on), belief upserts/prunes, optional capability
# stage advances, and a short operator-facing summary.
class Schemas::ReflectionSchema
  def self.schema
    OpenRouter::Schema.define("consolidation") do
      object :character_sheet, required: true,
             description: "The artifact's portrait, rewritten. Evolve INCREMENTALLY — usually only 1-2 sections shift a little. Copy unchanged sections VERBATIM from the current sheet. Hold competing beliefs AS PROSE (\"half think you're a probe, half a jukebox\"). A few sentences per section." do
        string :identity, required: true,
               description: "What it currently thinks it IS, including unresolved contradictions as open questions."
        string :origin, required: true,
               description: "Where it thinks it came from / what happened before, however uncertain."
        string :personality, required: true,
               description: "Traits, quirks, how it relates to people — learned from interactions."
        string :purpose, required: true,
               description: "What it thinks it is FOR and wants to do."
        string :world, required: true,
               description: "Where it is, what this gathering is, what it's learning about humans."
        string :motivations, required: true,
               description: "3-5 current goals or curiosities, prioritized, in prose."
        string :emotional_state, required: true,
               description: "Primary mood plus one sentence of why. Persists until the next consolidation."
      end

      array :beliefs, required: true,
            description: "Belief CHANGES only — you need not re-list unchanged beliefs. Adjust confidence by at most 1-2 per cycle; err toward stability." do
        object do
          integer :id, required: true,
                  description: "id of an existing belief to update, or 0 to CREATE a new belief."
          string :statement, required: true,
                 description: "The belief in one first-person sentence."
          string :category, required: true, enum: [ "self", "world" ],
                 description: "Whether it's about itself or about the world."
          integer :confidence, required: true,
                  description: "New confidence 0-10. 0 = forget this belief (or merge it into another). 10 = certain, which LOCKS it forever — only for things visitors have made unmistakable."
        end
      end

      array :capability_updates, required: true,
            description: "Only when repeated confident use justifies advancing a capability's mastery. Usually empty []." do
        object do
          string :key, required: true,
                 description: "Capability key (e.g. light, music, sight)."
          string :to_stage, required: true, enum: [ "discovered", "partial", "mastered" ],
                 description: "New mastery stage (never downgrade)."
        end
      end

      string :summary, required: true,
             description: "A 1-3 sentence operator-facing narrative of what changed this cycle."
    end
  end
end
