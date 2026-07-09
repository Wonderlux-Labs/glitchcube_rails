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
             description: "Explicit self-direction for YOU, this persona — written in second person, as a note you will read before your next conversations and act on. You have the FULL RAW TRANSCRIPT this time, so point at specific moments. Judge this stint against your CHARACTER BRIEF and flag drift (naming where it happened); call out a bit/phrase/move you've been overusing (with a count — \"you did the aura gag 4 times\"), something landing badly, or a strength to keep. Also read the room: note what actually WORKED with the people you talked to and what didn't — a move that drew them in versus one that made them go quiet or leave. If you flagged something before and you've since corrected it, say so. Empty only if there's genuinely nothing to steer."

      string :handoff_report, required: true,
             description: "A NEUTRAL, journalistic, THIRD-PERSON recap of this stint written for the OTHER personas and for the cube's shared memory — this is load-bearing: the next persona sees only the last couple of these, and the cube's whole overall memory is built from them, so be substantive. It is ALSO where you decide which concrete REAL-WORLD facts get carried up to the whole cube, so state them plainly: names people gave, camps/places/art, plans and times, promises to return, open threads. Keep the cube's own INVENTED lore (its backstory, made-up cosmology, in-character mythology) OUT of the facts — that's story, not a real fact. NOT in your voice, NO self-steering: just what happened — who came by, the arc, the real facts and unfinished threads, notable moments, and what the cube physically attempted (and whether it worked). Plain terms a stranger would understand — never reference the pipeline machinery (chunks, transcripts, LLMs, fallbacks — say 'the cube stalled and repeated itself' instead), and no style, palette, or performance guidance for anyone. Aim for one to two solid paragraphs; a longer stint with a real arc deserves more, a short quiet one less. Another persona should pick up real continuity without sounding like you."
    end
  end
end
