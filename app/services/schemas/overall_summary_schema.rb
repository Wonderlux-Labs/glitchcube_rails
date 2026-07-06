# app/services/schemas/overall_summary_schema.rb
#
# Structured output for OverallSummarizerService (the summary-of-summaries).
#   summary  — the single evolving long-term memory
#   ooc_note — SYSTEM-WIDE director notes: overall performance, acting, and system
#              functioning issues used to steer ALL personas
class Schemas::OverallSummarySchema
  def self.schema
    OpenRouter::Schema.define("overall_summary", strict: false) do
      string :summary, required: true,
             description: "The updated long-term memory of the whole event so far — 2-4 paragraphs. Keep what still matters, add what's new from the recent summaries, let go of transient detail. Preserve durable anchors: recurring people/regulars (by name), places/camps/events people keep mentioning, running themes, and how the overall mood has evolved."

      string :ooc_note, required: false,
             description: "SYSTEM-WIDE director notes — overall performance, acting, and system functioning. Flag PERSISTENT patterns visible across multiple summaries that steer ALL personas: a bit/catchphrase/move overused, characters slipping or blurring, the cube's actions/devices repeatedly failing (a real functional problem), or a tone landing badly. Direct and actionable. NOT part of the in-world memory. Empty only if nothing stands out."
    end
  end
end
