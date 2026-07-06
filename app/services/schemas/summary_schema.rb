# app/services/schemas/summary_schema.rb
#
# Structured output for SummarizerService. Three separable pieces:
#   summary          — the in-world running memory (how the conversations are going)
#   real_world_facts — concrete facts learned (names, plans, events, places)
#   ooc_note         — out-of-character steering note (the seed of "director steering")
class Schemas::SummarySchema
  def self.schema
    OpenRouter::Schema.define("interaction_summary", strict: false) do
      string :summary, required: true,
             description: "A short, honest in-world account of what these interactions were actually like — who came by, the vibe and how it's shifting, how conversations are going, anything memorable. Write it naturally, the way the cube would remember its night; not a checklist. A paragraph or two; a sentence is fine if little happened."

      string :real_world_facts, required: false,
             description: "Concrete, true-about-the-world things the cube learned that would matter in later conversations: names people gave, plans/events they mention (a party at the Corral later, the burn at midnight), what's happening around the event, camps/places/art. Just the facts, brief — a few lines. Empty if nothing concrete came up. (Keeping this separate from the story tends to surface useful specifics.)"

      string :ooc_note, required: false,
             description: "A private out-of-character note to the humans running the installation and the cube's future self — the ONLY place for steering. Flag: the cube's actions/devices repeatedly failing (a real functional problem, not flavor), a tic/loop/catchphrase a persona overuses, characters slipping or blurring, a move landing badly, or anyone genuinely distressed. Direct and actionable. Empty on most runs."
    end
  end
end
