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

      string :goal_progress,
             description: "Progress towards your current goal"

      # Single plain-English instruction describing every environment change you
      # want, in one sentence. A separate translator turns this into precise
      # device commands, so just describe the desired effect naturally.
      # Examples: "Turn the lights deep orange and play heavy metal",
      # "Dim everything and turn on the fan". Leave blank for no change.
      string :environment_instruction,
             description: "Plain-English description of all environment/device changes to make, or empty if none"

      # Explicit memory search requests. Results surface to you on the next turn.
      array :search_memories,
            description: "Specific memory searches to perform for additional context" do
        object do
          string :query, required: true,
                 description: "What to search for in memories"

          string :type,
                 description: "Type of memory to search",
                 enum: [ "summaries", "events", "people", "all" ],
                 default: "all"
        end
      end

      # Facts worth remembering long-term. Only flag things genuinely useful to
      # recall in future conversations (a name, a preference, a commitment) — not
      # small talk. These are persisted as ConversationMemory after the turn.
      array :memories,
            description: "New facts worth remembering for future conversations" do
        object do
          string :summary, required: true,
                 description: "The fact to remember, in one sentence"

          string :memory_type,
                 description: "Kind of memory",
                 enum: [ "preference", "fact", "instruction", "context", "event" ],
                 default: "fact"

          integer :importance,
                  description: "How important to remember, 1 (trivial) to 10 (critical)",
                  default: 5
        end
      end
    end
  end
end
