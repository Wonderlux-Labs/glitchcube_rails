# app/services/schemas/overall_summary_schema.rb
#
# Structured output for OverallSummarizerService — the cube's durable, structural digest of
# the whole event, folded from the neutral persona HANDOFF reports. Split into fields so the
# model does one clear job each and the context builder can render a scannable "world board":
#   shared_narrative   — the evolving in-world story of the event (structural, not literary)
#   durable_facts      — places/camps/events that keep coming up (the world board)
#   recurring_visitors — named anchors and what they're about
#   active_threads     — concrete unfinished business a visitor set up
#   director_note      — OPTIONAL cross-persona steering, only if a whole-cube pattern emerges
class Schemas::OverallSummarySchema
  def self.schema
    OpenRouter::Schema.define("overall_summary", strict: false) do
      string :shared_narrative, required: true,
             description: "The evolving story of the whole event so far — the common ground every persona leans on. Structural and grounded, not flowery. REWRITE it fresh in your own words each run: carry forward the FACTS and durable anchors (recurring people, places, running themes, how the mood has shifted) but never the previous narrative's sentences or phrasing, fold in what's new from the handoffs, and ROLL UP / COMPRESS older detail as the night grows rather than letting it sprawl. If grandiose language is accumulating ('legendary', 'has cemented itself'), flatten it back to plain reporting. Aim for 3-4 tight paragraphs (~400 words); if you're past that you're holding too much detail — compress older material into a sentence. If a condition affects the WHOLE cube (even a functional one like devices never responding), give it an in-world face here so every persona plays it the same way."

      string :durable_facts, required: false,
             description: "The 'world board' — REAL places, camps, and event facts visitors keep mentioning that stay true across the night, one short line each in the shape '<camp/place>: <what's true about it> (visitor-reported)'. ONLY facts that actually surfaced in the handoffs — never invent an entry, never write placeholder or 'not yet known' lines. Only real-world, visitor-reported facts — do NOT record the cube's own invented lore or backstory (where it was 'shipped from', its made-up mythology), and the cube's own mood, performance, or capabilities are not world facts either; all of that lives in the narrative, not the world board. Short bulleted lines. REBUILD this each run: carry forward the still-relevant facts from the current world board, fold in new ones from the handoffs, and DROP anything that's gone stale or been resolved. Keep it bounded — the ~5-8 most relevant, not an ever-growing log. These are the immersion wins — the cube knowing the actual event. Empty if nothing durable has surfaced."

      string :recurring_visitors, required: false,
             description: "Named anchors — people who gave a name and left an impression or a hook: 'Marco: asked for a deep lavender-purple glow, may return by sunrise'. Short lines, one per person. REBUILD each run: carry forward anchors still worth remembering, add new ones from the handoffs, and rotate OUT people who haven't come up in recent handoffs. Keep to the ~5 most relevant. Empty if no one recurring has surfaced."

      string :active_threads, required: false,
             description: "Concrete unfinished business a REAL VISITOR set up that a later persona could pick up: someone who said they'd be back ('Laurie's returning at midnight for a reading'), a plan, a promise, a place they were headed. Only things visitors actually said — NOT lore the cube invented. REBUILD each run: carry forward threads still open, add new ones, and DROP threads that have been resolved or clearly expired (a midnight plan is stale by 3am). One or two lines. Empty if nothing is pending."

      string :director_note, required: false,
             description: "OPTIONAL cross-persona steering — leave empty unless a genuine WHOLE-CUBE pattern jumps out across the handoffs that no single persona could see: the cube's devices failing across every stint, all personas blurring into the same tone, a whole-event approach landing badly. Corrective, not creative: flag a problem or pattern to fix — never direct all personas to adopt one persona's bit, style, or storyline, and never assign emotional homework ('keep X sacred'). If it's fun rather than broken, leave it empty. Do NOT feel obligated to produce one; steering mostly lives per-persona. Only write it when something system-wide is clearly there."
    end
  end
end
