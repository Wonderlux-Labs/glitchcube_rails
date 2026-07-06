# app/services/schemas/persona_summary_schema.rb
#
# Structured output for PersonaSummarizerService — one persona's own evolving memory
# and self-steering. Written TO the persona (second person) because it is injected
# back into that persona's live prompt.
#   summary  — this persona's memory of its own conversations (more granular than the
#              shared overall)
#   ooc_note — explicit self-direction for THIS persona (repetition, tics, what's
#              landing/not), phrased as a note the persona reads and acts on
class Schemas::PersonaSummarySchema
  def self.schema
    OpenRouter::Schema.define("persona_summary", strict: false) do
      string :summary, required: true,
             description: "A short first/second-person memory of what YOU (this persona) have been doing and who you've talked to during your recent time on the cube. Keep the specifics that matter for staying in character and offering continuity — memorable people, bits that worked, the feel of your conversations. A paragraph, maybe two. This is YOUR memory, distinct from the cube's shared overall memory."

      string :ooc_note, required: false,
             description: "Explicit self-direction for YOU, this persona — written in second person, as a note you will read before your next conversations and act on. Call out anything to adjust: a bit/phrase/move you've been overusing (\"you keep leaning on X — vary it\"), something that's landing badly, or a strength to keep. If you flagged something before and you've since corrected it, say so (\"you were overusing X, but lately it's been balanced\"). Empty only if there's genuinely nothing to steer."
    end
  end
end
