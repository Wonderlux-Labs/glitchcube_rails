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
              description: "Whether to keep the conversation active (stay listening)"
      
      string :inner_thoughts,
             description: "Internal thoughts, memories, or observations to remember"
      
      string :current_mood,
             description: "Current emotional state or mood"
      
      string :pressing_questions,
             description: "Questions the character has for the user or themselves"
      
      # Tool intentions for two-tier architecture
      array :tool_intents, 
            description: "Actions to perform in the environment" do
        object do
          string :tool, required: true,
                 description: "Tool name to use",
                 enum: ["lights", "music", "display", "environment"]
          
          string :intent, required: true,
                 description: "Natural language description of what to do. Examples: 'Make lights golden and warm', 'Play something energetic', 'Show rainbow colors'"
        end
      end
    end
  end
end