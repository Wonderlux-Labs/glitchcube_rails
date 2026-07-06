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
  ACTION_CHANNELS = %w[cube_light top_light sound announcement marquee camera].freeze

  def self.schema
    OpenRouter::Schema.define("narrative_response", strict: false) do
      string :speech, required: true,
             description: "The words your character says out loud. This text is sent DIRECTLY to text-to-speech and spoken aloud in your character's voice — write only what should be heard. No stage directions, asterisks, or parentheses. You MAY use ellipses (...), commas, dashes, and question marks to shape natural pacing and delivery."

      string :inner_monologue, required: true,
             description: "What your character is thinking privately this turn. Never spoken aloud. Can contradict the speech. A sentence or two."

      array :actions,
            description: "Physical things you want to do to your environment this turn. Use an empty list unless you actually want to change something — you do NOT need to act every turn; most turns are just talk. You are free to act any time and to be playful, ironic, or contradictory (e.g. play someone's song while the marquee reads 'THIS SONG SUCKS, SORRY FOR PLAYING IT')." do
        object do
          string :action_name, required: true,
                 description: "The channel to use: one of cube_light, top_light, sound, announcement, marquee, camera."
          string :description, required: true,
                 description: "Plain-English description of what you want on that channel, e.g. 'warm amber and dim', 'play something slow and moody', 'scroll THE STARS FORGOT YOUR NAME'. A separate agent turns this into real device commands, so describe intent, not exact settings."
        end
      end

      boolean :continue_conversation, required: true,
              description: "Whether to keep listening without a wake word. Err toward true; false only when the conversation has clearly ended (a goodbye) or the input is environmental noise, not someone talking to you."

      string :urgent_question, required: false,
             description: "OPTIONAL and EXPENSIVE — leave this out on almost every turn. Only fill it in if you genuinely need to recall something from your past interactions to respond well (e.g. a returning visitor references something you can't place, or someone asks what happened earlier). Put ONE plain-English question here; it triggers a slow background search across everything you've experienced, and any answer arrives a turn or two later, not right now. Use sparingly — most turns don't need it."
    end
  end
end
