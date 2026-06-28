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

      # Single plain-English instruction describing every environment change you
      # want, in one sentence. A separate translator turns this into precise
      # device commands, so just describe the desired effect naturally.
      # Examples: "Turn the lights deep orange and play heavy metal",
      # "Dim everything and turn on the fan". Leave blank for no change.
      string :environment_instruction,
             description: "Plain-English description of all environment/device changes to make, or empty if none"

      # Optional deep recall. Only when you genuinely want to dig past the
      # world-state already in your context. Results surface on the next turn.
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
