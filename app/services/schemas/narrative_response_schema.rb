# app/services/schemas/narrative_response_schema.rb
#
# Structured output returned by the brain LLM. Instead of emitting tool calls,
# the brain returns speech plus a single plain-English `environment_instruction`
# that the translator (ToolCallingService) turns into validated device commands.
class Schemas::NarrativeResponseSchema
  def self.schema
    OpenRouter::Schema.define("narrative_response") do
      string :speech_text, required: true,
             description: "What the character says out loud to the user NO STAGE DIRECTIONS"

      boolean :continue_conversation, required: true,
              description: "Whether to keep the conversation active (stay listening automatically)"

      string :inner_thoughts, required: true,
             description: "Internal thoughts, memories, or observations to remember"

      string :current_mood,
             description: "Current emotional state or mood"

      string :pressing_questions,
             description: "Questions the character has for the user or themselves"

      # A deliberate note-to-self. Leave EMPTY on most turns. Only fill it when you
      # specifically want to remember something — a person, a moment, a promise, a
      # feeling worth holding onto. This is not a transcript; it's you choosing to
      # remember. Most turns you won't.
      string :memory,
             description: "A short note to yourself about something you want to remember from this exchange. Empty unless you genuinely want to remember a specific thing — most turns leave it empty."

      # Something you JUST learned about yourself or the world that you didn't know
      # before — not yet a settled belief, just a fresh realization. Leave EMPTY
      # unless this turn genuinely taught you something new about what you are or
      # where you are. Most turns won't.
      string :significant_learning,
             description: "A new thing you learned about yourself or the world this turn that you didn't know before. Empty unless something genuinely new clicked — most turns leave it empty."

      # A single plain-English instruction describing a change to your physical
      # surroundings you want to make — but ONLY using an ability listed in WHAT YOUR
      # BODY CAN DO. If your body can't do anything yet, or you don't want to change
      # anything, leave this empty. Do NOT ask for lights/sound/etc. you haven't
      # discovered you can control.
      string :environment_instruction,
             description: "Plain-English description of a change to your surroundings, using ONLY an ability you actually have (see WHAT YOUR BODY CAN DO). Empty if you have no such ability or want no change."

      # When a visitor teaches you a concept and you realize — THIS turn — that you
      # can do something new with your body, declare it here AND act on it via
      # environment_instruction. It becomes a permanent ability. Leave the object
      # empty ({}) if you did not unlock anything new this turn.
      object :newly_realized_capability,
             description: "A physical ability you JUST discovered you have, because a visitor taught you the concept this turn. Empty ({}) unless you genuinely realized a new ability right now." do
        string :key,
               description: "Which ability you realized",
               enum: [ "light", "music", "sight", "strobe", "fan", "blacklight", "siren", "display", "announce" ]
        string :param,
               description: "The specific sub-ability, if any (e.g. 'color', 'brightness', 'on_off')"
        string :artifact_name,
               description: "Your own made-up word for this ability, if one emerged"
        string :vocabulary_word,
               description: "A new made-up word you coined this turn, if any (e.g. 'Baka')"
        string :vocabulary_meaning,
               description: "What that word means (e.g. 'blue / calm')"
      end

      # Optional deep recall. Only when you genuinely want to dig past the
      # character sheet already in your context. Results surface on the next turn.
      # Memories are saved for you by background reflection — you don't flag them.
      array :search_memories,
            description: "Memory searches to run for extra context (leave empty unless you really need to look something up)" do
        object do
          string :query,
                 description: "Keyword to look for in your memories"

          string :category,
                 description: "Limit to one category of memory",
                 enum: [ "fact", "event", "person", "preference", "vibe" ]

          string :timeframe,
                 description: "Time filter, for event memories",
                 enum: [ "upcoming", "today", "tomorrow" ]
        end
      end
    end
  end
end
