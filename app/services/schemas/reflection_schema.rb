# frozen_string_literal: true

# Structured output for the reflection job. The cube reads recent conversations
# and returns: a rewritten short world-state (injected into every prompt), a
# brief narrative of this period (archived for future trend analysis), and any
# discrete memories worth keeping.
class Schemas::ReflectionSchema
  def self.schema
    OpenRouter::Schema.define("reflection") do
      string :world_state, required: true,
             description: "The cube's CURRENT continuity, rewritten fresh and kept SHORT (a few sentences, max ~150 words). What's true right now that should color every conversation: recent recurring questions, the current social vibe, anything it was just told about the event, how it's feeling. Merge with the prior world-state provided — drop what's stale, keep what still matters. Plain prose, no headers."

      string :summary, required: true,
             description: "A brief 1-3 sentence narrative of what happened across these conversations, for the historical record."

      array :memories,
            description: "Discrete facts worth remembering and searching later. Only genuinely useful things (a person, a commitment, an upcoming event, a strong preference) — not small talk." do
        object do
          string :content, required: true,
                 description: "The memory in one sentence."
          string :category,
                 description: "Kind of memory",
                 enum: [ "fact", "event", "person", "preference", "vibe" ],
                 default: "fact"
          integer :importance,
                  description: "1 (trivial) to 10 (critical)",
                  default: 5
          string :emotion,
                 description: "How the cube felt about this, if notable (e.g. amused, unsettled)"
          string :occurs_at,
                 description: "ISO8601 datetime, ONLY for category=event that happens at a specific future/past time. Omit otherwise."
        end
      end
    end
  end
end
