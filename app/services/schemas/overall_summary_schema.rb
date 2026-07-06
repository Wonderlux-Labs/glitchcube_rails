# app/services/schemas/overall_summary_schema.rb
#
# Structured output for OverallSummarizerService (the summary-of-summaries). Split into
# three distinct fields so the model does one clear job per field instead of cramming the
# whole event + pending threads + cross-persona steering into one rambling blob:
#   shared_narrative — the single evolving in-world memory of the event (injected as story)
#   active_threads   — concrete unfinished business a VISITOR set up (not invented lore)
#   director_note    — cross-persona steering the personas read and act on next turn
class Schemas::OverallSummarySchema
  def self.schema
    OpenRouter::Schema.define("overall_summary", strict: false) do
      string :shared_narrative, required: true,
             description: "The updated in-world long-term memory of the whole event so far — 3-4 paragraphs, ~300-350 words. Keep what still matters, add what's new from the recent summaries, let transient detail go. Preserve durable anchors: recurring people/regulars (by name), places/camps/events people keep mentioning, running themes, and how the overall mood has evolved. If some condition affects the WHOLE cube (even a functional one like devices never responding), give it an in-world face here as a shared theme so every persona plays it the same way."

      string :active_threads, required: false,
             description: "Concrete unfinished business a REAL VISITOR set up that a later persona could pick up: someone who gave a name and said they'd come back ('Laurie's returning at midnight for a reading'), a plan, a promise, a place they were headed. Only things visitors actually said or committed to — NOT lore the cube invented itself (made-up camps, fictional events). One or two lines, plainest facts. Empty if nothing concrete is pending."

      string :director_note, required: false,
             description: "Cross-persona steering the personas read and act on next turn (there is NO human operator — this is prompt-steering, not a report). Flag PERSISTENT patterns visible across multiple summaries that no single persona could see: a bit/catchphrase/move overused across the board, characters slipping or blurring into each other, the cube's actions/devices repeatedly failing (flag it plainly as a real functional problem even though the narrative also gives it an in-world face), or a whole-event tone landing badly. Direct and actionable, addressed to all the personas. Empty only if nothing system-wide stands out."
    end
  end
end
