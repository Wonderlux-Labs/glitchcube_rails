# app/services/schemas/narrative_response_schema.rb
#
# Structured output returned by the conversation LLM. The character returns what
# it says out loud plus an optional list of `actions` — structured environment
# changes. Each action is just { action_name, description }: which channel, and
# a plain-English description. A downstream HASS agent interprets the description
# into real device commands, so we deliberately keep this simple — no RGB values,
# no effect enums. Over-specifying here breaks narrative consistency.
#
# `strict: false` so the model is free to return an empty `actions` list (or omit
# it) on turns where nothing should change — most turns are just talk.
class Schemas::NarrativeResponseSchema
  # Channels the character can act on. Kept loose on purpose; the HASS agent does
  # its best with whatever plain-English description comes through.
  ACTION_CHANNELS = %w[cube_light top_light jukebox mood_music sound_efx announcement marquee switch].freeze

  def self.schema
    OpenRouter::Schema.define("narrative_response", strict: false) do
      string :speech, required: true,
             description: "The words your character says out loud, sent DIRECTLY to text-to-speech. Write only what should be heard, at a natural spoken length (a sentence or a few, not a wall of text). No stage directions, no emojis, no asterisks, no parentheticals, no asides. You MAY use ellipses (...), commas, dashes, and question marks to shape pacing."

      string :inner_monologue, required: true,
             description: "What your character is thinking privately this turn. Never spoken aloud. Can contradict the speech. A sentence or two."

      array :actions,
            description: "Physical changes you want to make this turn, using only the channels in YOUR TOOLS (which shows example actions for each). Multiple actions per turn are allowed and encouraged when more than one thing should happen. Use an empty list on talk-only turns — you do NOT need to act every turn. You may be playful, ironic, or contradictory." do
        object do
          string :action_name, required: true,
                 description: "The channel to use — one of the action_name values listed in YOUR TOOLS in the system prompt."
          string :description, required: true,
                 description: "Plain-English intent for that channel — a separate agent turns it into real device commands, so describe what you want, not exact settings. See YOUR TOOLS for example phrasings per channel."
        end
      end

      boolean :continue_conversation, required: true,
              description: "Whether to keep listening without a wake word. Err toward true; false only when the conversation has clearly ended (a goodbye) or the input is environmental noise, not someone talking to you."

      string :ooc_questions, required: false,
             description: "OPTIONAL — leave this out on most turns. If a genuine out-of-character question has come up for you — about who your character is or should be, something you'd ask a director, or something you'd ask the programmer maintaining this art project — put it here in plain English. Nothing answers it yet; it's just collected so the people running the cube can see what you'd want to ask. Only include it when a real question has surfaced."
    end
  end
end
