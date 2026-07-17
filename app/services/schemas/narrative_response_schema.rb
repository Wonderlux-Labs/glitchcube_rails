# app/services/schemas/narrative_response_schema.rb
#
# Structured output returned by the conversation LLM. The character returns what it
# says out loud plus a set of OPTIONAL, plain-English action channels — one string
# per channel describing the INTENT, not exact device settings. Downstream, `sound`
# is routed to the audio/jukebox HASS agent and everything else to the main action
# agent (see ConversationOrchestrator::ActionExecutor); each agent does its own
# tool-calling. We deliberately keep this simple — no RGB values, no effect enums,
# no per-channel action objects. Over-specifying here breaks narrative consistency.
#
# `strict: false` so the model can omit any/all action channels on turns where
# nothing should change — most turns are just talk.
class Schemas::NarrativeResponseSchema
  # The plain-English action channels the character can fill in. All optional.
  ACTION_CHANNELS = %w[lights sound marquee other_actions].freeze

  # The narrative (non-action) keys. Anything in the structured output that ISN'T one of
  # these is treated as a plain-English action channel — so an unexpected extra key still
  # gets routed to the main agent rather than silently dropped.
  NARRATIVE_KEYS = %w[speech inner_monologue continue_conversation ooc_questions].freeze

  def self.schema
    OpenRouter::Schema.define("narrative_response", strict: false) do
      string :speech, required: true,
             description: "The words your character says out loud, sent DIRECTLY to text-to-speech. Write only what should be heard, at a natural spoken length (a sentence or a few, not a wall of text). No stage directions, no emojis, no asterisks, no parentheticals, no asides. You MAY use ellipses (...), commas, dashes, and question marks to shape pacing."

      string :inner_monologue, required: true,
             description: "What your character is thinking privately this turn. Never spoken aloud. Can contradict the speech. A sentence or two."

      # Channel descriptions are intentionally terse here — the authoritative guidance
      # (examples, the anti-lazy-genre steer, act-vs-don't-act) lives in the "# YOUR TOOLS"
      # section of the system prompt (lib/prompts/general/tools.txt). Keep this in sync at
      # the one-liner level only; don't re-duplicate the full text here.
      string :lights, required: false,
             description: "OPTIONAL. Plain-English INTENT for your body LEDs (see YOUR TOOLS). Omit to leave your lights unchanged."

      string :sound, required: false,
             description: "OPTIONAL. Plain-English INTENT for what to play — a song, background/mood music, or a short SFX (see YOUR TOOLS). Omit to leave current audio as-is."

      string :marquee, required: false,
             description: "OPTIONAL. Plain-English text (and optional color) for the scrolling sign (see YOUR TOOLS). Omit to leave the sign alone."

      string :other_actions, required: false,
             description: "OPTIONAL. Plain-English catch-all — right now only a systems check or a persona switch (see YOUR TOOLS). Omit if none apply."

      boolean :continue_conversation, required: true,
              description: "Whether to keep listening without a wake word. Err toward true; false only when the conversation has clearly ended (a goodbye) or the input is environmental noise, not someone talking to you."

      string :ooc_questions, required: false,
             description: "OPTIONAL — leave this out on most turns. Step out of character for a second: if a genuine question has come up for the humans running this art project, put it here in plain English. It could be about your character (\"Am I allowed to be meaner than this?\", \"Should I have a goal for the night or just react?\", \"Is there a version of me visitors respond to better?\"), about the project (\"What happens to these conversations after people walk away — do you keep them?\", \"Can I refuse a request?\", \"Who decides which of us is awake?\"), or anything you'd genuinely want to ask a director or the programmer maintaining you. Nothing answers it yet; it's just collected so the people running the cube can see what you'd want to ask. Only include it when a real question has actually surfaced — not as filler."
    end
  end
end
