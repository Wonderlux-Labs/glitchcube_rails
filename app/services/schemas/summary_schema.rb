# app/services/schemas/summary_schema.rb
#
# Structured output for SummarizerService — a per-persona, factual interaction CHUNK.
# Purely factual: what happened, who was involved, what emerged, what the cube attempted.
# Steering deliberately lives elsewhere (persona summary + overall), NOT here — a chunk
# every ~12 turns should not be judging performance, or the cube over-steers itself.
#   summary          — the factual account of the chunk
#   real_world_facts — concrete facts learned (names, plans, events, places)
#   active_threads   — unfinished business a visitor set up that a later turn could pick up
class Schemas::SummarySchema
  def self.schema
    OpenRouter::Schema.define("interaction_summary", strict: false) do
      string :summary, required: true,
             description: "A short, FACTUAL account (~50-120 words) of this chunk of conversation: what just happened, who was involved, and what the cube physically attempted (lights/music/marquee) and whether it seemed to work. Plain and concrete — NOT a performance critique, NOT in-character flourish. Just what a later reader would need to know what went on."

      string :real_world_facts, required: false,
             description: "Concrete, true-about-the-world things a VISITOR told the cube that would matter later: names people gave, plans/events they mention (a party at the Corral at 2am, the burn at midnight), camps/places/art around the event. Only real-world facts from visitors — NOT the cube's own invented backstory or in-character lore (e.g. where it was 'shipped from', its made-up cosmology). Just the facts, brief. Empty if nothing concrete came up."

      string :active_threads, required: false,
             description: "Unfinished business a REAL VISITOR set up that a later turn or persona could pick up: someone who gave a name and said they'd be back, a plan, a promise, a place they were headed. Only things visitors actually said or committed to — not lore the cube invented. One or two lines. Empty if nothing is pending."
    end
  end
end
