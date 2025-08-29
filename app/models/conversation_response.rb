# app/models/conversation_response.rb
class ConversationResponse
  include AiStructuredResponse

  # Define the schema matching Home Assistant's conversation.process API response format
  ai_schema do |s|
    s.string :response_type, enum: [ "action_done", "query_answer", "error" ],
             description: "Type of response: action_done for executed actions, query_answer for answers, error for failures"

    s.string :language, default: "en",
             description: "Language of the response"

    s.object :speech, description: "Speech output for the Cube" do
      s.object :plain, description: "Plain text speech" do
        s.string :speech, required: true,
                 description: "The actual text to be spoken"
      end
    end

    s.object :data, description: "Response data containing targets and results" do
      s.array :targets, description: "Intent targets applied from general to specific" do
        s.string :entity_id, description: "Entity ID that was targeted"
        s.string :name, description: "Human readable name of the target"
        s.string :domain, description: "Domain of the entity (light, switch, etc.)"
      end

      s.array :success, description: "Entities that were successfully acted upon" do
        s.string :entity_id, description: "Entity ID that succeeded"
        s.string :name, description: "Human readable name"
        s.string :state, description: "New state of the entity"
      end

      s.array :failed, description: "Entities where the action failed" do
        s.string :entity_id, description: "Entity ID that failed"
        s.string :name, description: "Human readable name"
        s.string :error, description: "Error message describing the failure"
      end
    end

    s.boolean :continue_conversation, default: false,
              description: "Whether the conversation agent expects a follow-up from the user"

    s.string :conversation_id, description: "Unique ID to track this conversation"
  end

  # ActiveModel attributes matching our schema
  attribute :response_type, :string
  attribute :language, :string, default: "en"
  attribute :continue_conversation, :boolean, default: false
  attribute :conversation_id, :string

  # Nested attributes for speech
  attribute :speech_plain_text, :string

  # Arrays for data
  attribute :targets, array: true, default: []
  attribute :success_entities, array: true, default: []
  attribute :failed_entities, array: true, default: []

  # Validations
  validates :response_type, inclusion: { in: %w[action_done query_answer error] }
  validates :speech_plain_text, presence: true
  validates :language, presence: true

  # Custom methods for easier access
  def speech
    result = {}

    if speech_plain_text.present?
      result[:plain] = { speech: speech_plain_text }
    end

    result
  end

  def data
    {
      targets: targets || [],
      success: success_entities || [],
      failed: failed_entities || []
    }
  end

  # Convert to Home Assistant compatible format
  def to_home_assistant_response
    {
      continue_conversation: continue_conversation,
      response: {
        response_type: response_type,
        language: language,
        data: data,
        speech: speech
      },
      conversation_id: conversation_id
    }
  end

  # Helper methods for different response types
  def self.action_done(speech_text, success_entities: [], failed_entities: [], targets: [], **options)
    new(
      response_type: "action_done",
      speech_plain_text: speech_text,
      success_entities: success_entities,
      failed_entities: failed_entities,
      targets: targets,
      **options
    )
  end

  def self.query_answer(speech_text, **options)
    new(
      response_type: "query_answer",
      speech_plain_text: speech_text,
      **options
    )
  end

  def self.error(speech_text, error_details: [], **options)
    new(
      response_type: "error",
      speech_plain_text: speech_text,
      failed_entities: error_details,
      **options
    )
  end

  private
end
