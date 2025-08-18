# app/models/concerns/ai_structured_response.rb
module AiStructuredResponse
  extend ActiveSupport::Concern

  included do
    include ActiveModel::Model
    include ActiveModel::Attributes
    include ActiveModel::Validations
    include ActiveModel::Serialization

    class_attribute :_ai_schema

    # Store the raw response and metadata
    attr_accessor :_raw_response, :_ai_metadata, :_confidence_score
  end

  class_methods do
    # Define the schema for this response type
    def ai_schema(name = nil, &block)
      schema_name = name || self.name.underscore
      self._ai_schema = OpenRouter::Schema.define(schema_name, &block)
    end

    # Generate a response using AI with auto-healing enabled
    def ai_generate(prompt, model: nil, **options)
      client = ai_client

      # Always use our schema and force structured output with auto-healing
      response = client.complete(
        prepare_messages(prompt, options),
        model: model || default_model,
        response_format: _ai_schema,
        force_structured_output: true, # Always force structured format
        **options.except(:messages, :prompt, :model)
      )

      from_ai_response(response)
    end

    # Create instance from OpenRouter response
    def from_ai_response(response)
      instance = new
      instance._raw_response = response
      instance._ai_metadata = extract_metadata(response)

      # Always try to parse structured output with auto-healing
      begin
        # Auto-healing is enabled by default in your gem
        data = response.structured_output(auto_heal: true)
        populate_from_data(instance, data) if data
        instance._confidence_score = :high
      rescue OpenRouter::StructuredOutputError => e
        Rails.logger.error "AI structured output failed after healing: #{e.message}"
        # Store the error for debugging
        instance._ai_metadata[:parsing_error] = e.message
        instance._confidence_score = :failed
      end

      instance
    end

    private

    def ai_client
      @ai_client ||= begin
        # Build on the existing OpenRouter client configuration
        base_client = OpenRouter.client

        # Create a new client with enhanced configuration for structured responses
        OpenRouter::Client.new(
          api_key: base_client.api_key,
          app_name: base_client.app_name,
          site_url: base_client.site_url
        ) do |config|
          config.auto_heal_responses = true
          config.healer_model = "openai/gpt-4o-mini"
          config.max_heal_attempts = 3
        end
      end
    end

    def default_model
      # Set a reasonable default model
      Rails.configuration.default_ai_model
    end

    def prepare_messages(prompt, options)
      messages = case prompt
      when String
                   [ { role: "user", content: prompt } ]
      when Array
                   prompt
      when Hash
                   [ prompt ]
      else
                   raise ArgumentError, "Prompt must be String, Array, or Hash"
      end

      # Add system message if provided in options
      if options[:system_message]
        messages.unshift({ role: "system", content: options[:system_message] })
      end

      messages
    end

    def populate_from_data(instance, data)
      data.each do |key, value|
        setter_method = "#{key}="
        if instance.respond_to?(setter_method)
          instance.public_send(setter_method, value)
        else
          # Store unknown fields in metadata for debugging
          instance._ai_metadata ||= {}
          instance._ai_metadata[:unknown_fields] ||= {}
          instance._ai_metadata[:unknown_fields][key] = value
        end
      end
    end

    def extract_metadata(response)
      {
        model_used: response.model,
        usage: response.usage,
        response_id: response.id,
        created_at: Time.at(response.created),
        has_tool_calls: response.has_tool_calls?,
        tool_calls_count: response.tool_calls.size,
        raw_content: response.content,
        forced_extraction: response.instance_variable_get(:@forced_extraction)
      }
    end
  end

  # Instance methods
  def ai_metadata
    @_ai_metadata || {}
  end

  def ai_confidence
    @_confidence_score || :unknown
  end

  def ai_successful?
    ai_confidence == :high
  end

  def ai_failed?
    ai_confidence == :failed
  end

  def regenerate(model: nil, **options)
    raise "Cannot regenerate without original prompt" unless ai_metadata[:original_prompt]

    self.class.ai_generate(ai_metadata[:original_prompt], model: model, **options)
  end

  def to_hash
    attributes.except("_raw_response", "_ai_metadata", "_confidence_score")
  end

  def as_json(options = {})
    hash = to_hash
    if options[:include_metadata]
      hash[:_metadata] = {
        confidence: ai_confidence,
        model_used: ai_metadata[:model_used],
        usage: ai_metadata[:usage],
        forced_extraction: ai_metadata[:forced_extraction]
      }
    end
    hash
  end
end
