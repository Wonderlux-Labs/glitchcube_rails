# app/services/schemas/persona_summary_schema.rb
#
# Structured output for PersonaSummarizerService — produced in ONE call when a persona's
# stint ends. Three outputs with two audiences:
#   summary        — this persona's own evolving memory (written TO itself, second person)
#   ooc_note       — this persona's explicit self-steering (the deep steering lives here)
#   handoff_report — a NEUTRAL, journalistic recap for the OTHER personas + the overall digest
class Schemas::PersonaSummarySchema
  def self.schema
    OpenRouter::Schema.define("persona_summary", strict: false) do
      string :summary, required: true,
             description: "A short first/second-person memory of what YOU (this persona) have been doing and who you've talked to during your recent time on the cube. Keep the specifics that matter for staying in character and offering continuity — memorable people, bits that worked, the feel of your conversations. A paragraph, maybe two. This is YOUR memory, distinct from the cube's shared overall memory."

      string :ooc_note, required: false,
             description: "Explicit self-direction for YOU, this persona — written in second person, as a note you will read before your next conversations and act on. Judge this stint against your CHARACTER BRIEF and flag drift; call out a bit/phrase/move you've been overusing (\"you keep leaning on X — vary it\"), something landing badly, or a strength to keep. If you flagged something before and you've since corrected it, say so. Empty only if there's genuinely nothing to steer."

      string :handoff_report, required: true,
             description: "A NEUTRAL, journalistic, THIRD-PERSON recap of this stint written for the OTHER personas and for the cube's shared memory — this is load-bearing: the next persona sees only the last couple of these, and the cube's whole overall memory is built from them, so be substantive. NOT in your voice, NO self-steering: just what happened while you were on — who came by, the arc of the stint, facts and unfinished threads that emerged, notable moments, and what the cube physically attempted (and whether it worked). Aim for one to two solid paragraphs; a longer stint with a real arc deserves more, a short quiet one less. Another persona should be able to read it and pick up real continuity without sounding like you."
    end
  end
end
