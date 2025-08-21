# app/services/schemas/narrative_response_schema.rb
#
# Schema for structured narrative responses in two-tier architecture
# Narrative LLM returns this structure instead of using tool calls
class Schemas::NarrativeResponseSchema
  def self.schema
    OpenRouter::Schema.define("narrative_response") do
      string :speech_text, required: true,
             description: "What the character says out loud to the user"

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

      array :tool_intents,
            description: "Actions to perform in the environment via Home Assistant agent" do
        object do
          string :tool, required: true,
                 description: "Tool name to use",
                 enum: [ "lights", "music", "display", "environment" ]

          string :intent, required: true,
                 description: "Natural language description of what to do. Examples: 'Make lights golden and warm', 'Play something energetic', 'Show rainbow colors'"
        end
      end

      # Direct tool calls for immediate execution
      array :direct_tool_calls,
            description: "Tools to execute directly and synchronously (for queries and immediate actions)" do
        object do
          string :tool_name, required: true,
                 description: "Exact tool name to execute",
                 enum: [ "rag_search", "get_light_state", "display_notification" ]

          object :parameters,
                 description: "Tool parameters as key-value pairs",
                 additional_properties: true
        end
      end

      # Explicit memory search requests
      array :search_memories,
            description: "Specific memory searches to perform for additional context" do
        object do
          string :query, required: true,
                 description: "What to search for in memories"

          string :type,
                 description: "Type of memory to search",
                 enum: [ "summaries", "events", "people", "all" ],
                 default: "all"

          integer :limit,
                  description: "Maximum results to return",
                  minimum: 1,
                  maximum: 10,
                  default: 3
        end
      end
    end
  end
end
