# app/services/llm_service.rb
require "ostruct"

class LlmService
  class << self
    # Main conversation call with tool support
    def call_with_tools(messages:, tools: [], model: nil, **options)
      model_to_use = model || Rails.configuration.default_ai_model

      Rails.logger.info "🤖 LLM call with tools: #{model_to_use}"
      Rails.logger.info "🔧 Tools available: #{tools.length} - #{tools.map(&:name).join(', ')}"
      Rails.logger.info "📝 Last message: #{messages.last&.dig(:content)&.first(200)}..."
      Rails.logger.debug "📚 Full messages: #{messages.map { |m| "#{m[:role]}: #{m[:content]&.first(100)}..." }.join(' | ')}"

      begin
        # Prepare extras with OpenRouter-specific parameters
        extras = {
          temperature: options[:temperature] || 0.9,
          max_tokens: options[:max_tokens] || 32000
        }.merge(options.except(:temperature, :max_tokens))

        client = OpenRouter::Client.new

        # Log the full request being sent
        Rails.logger.info "🚀 OpenRouter Request:"
        Rails.logger.info "   Model: #{model_to_use}"
        Rails.logger.info "   Tool choice: #{tools.any? ? 'auto' : nil}"
        Rails.logger.info "   Extras: #{extras.inspect}"
        Rails.logger.info "   Tools: #{tools.length} tools - #{tools.map(&:name).join(', ')}"
        Rails.logger.info "📋 FULL REQUEST DETAILS:"
        Rails.logger.info "   Messages (#{messages.length}):"
        messages.each_with_index do |msg, i|
          Rails.logger.info "     [#{i+1}] #{msg[:role]}: #{msg[:content]&.first(500)}#{'...' if msg[:content]&.length.to_i > 500}"
        end
        if tools.any?
          Rails.logger.info "   Tool Definitions:"
          tools.each_with_index do |tool, i|
            Rails.logger.info "     [#{i+1}] #{tool.name}: #{tool.description}"
            Rails.logger.info "         Parameters: #{tool.parameters.inspect}"
          end
        end

        response = client.complete(
          messages,
          model: model_to_use,
          tools: tools, # Pass tools directly, no serialization needed
          tool_choice: tools.any? ? "auto" : nil,
          extras: extras
        )

        # Log the full response received
        Rails.logger.info "📥 OpenRouter Response:"
        Rails.logger.info "   Content: #{response.content&.first(500)}#{'...' if response.content&.length.to_i > 500}"
        Rails.logger.info "   Model: #{response.model}"
        Rails.logger.info "   Usage: #{response.usage}"
        Rails.logger.info "   Tool calls: #{response.tool_calls&.length || 0}"
        if response.tool_calls&.any?
          response.tool_calls.each_with_index do |tc, i|
            Rails.logger.info "     [#{i+1}] #{tc.name}: #{tc.arguments}"
          end
        end
        Rails.logger.info "📄 FULL RAW RESPONSE:"
        Rails.logger.info "#{JSON.pretty_generate(response.raw_response)}"

        Rails.logger.info "✅ LLM response received: #{response.content&.first(100)}..."

        if response.has_tool_calls?
          Rails.logger.info "🔧 Tool calls requested: #{response.tool_calls.map(&:name).join(', ')}"
          response.tool_calls.each_with_index do |tc, i|
            Rails.logger.debug "   Tool #{i+1}: #{tc.name} with args: #{tc.arguments}"
          end
        end

        # Return the actual OpenRouter response object
        response

      rescue StandardError => e
        Rails.logger.error "❌ LLM call failed: #{e.message}"
        Rails.logger.error "❌ Error class: #{e.class}"
        Rails.logger.error "❌ Error details: #{e.inspect}"
        Rails.logger.error e.backtrace.join("\n")

        # Return error response that mimics OpenRouter::Response interface
        OpenStruct.new(
          content: "I'm having trouble thinking right now. Please try again.",
          tool_calls: [],
          has_tool_calls?: false,
          usage: { prompt_tokens: 0, completion_tokens: 0 },
          model: model_to_use,
          error: e.message
        )
      end
    end

    # Main conversation call with structured output (no tools)
    def call_with_structured_output(messages:, response_format:, model: nil, **options)
      model_to_use = model || Rails.configuration.default_ai_model

      Rails.logger.info "🤖 LLM call with structured output: #{model_to_use}"
      Rails.logger.info "📊 Response format: #{response_format.name}"
      Rails.logger.info "📝 Last message: #{messages.last&.dig(:content)&.first(200)}..."
      Rails.logger.debug "📚 Full messages: #{messages.map { |m| "#{m[:role]}: #{m[:content]&.first(100)}..." }.join(' | ')}"

      begin
        # Prepare extras with OpenRouter-specific parameters
        extras = {
          temperature: options[:temperature] || 0.9,
          max_tokens: options[:max_tokens] || 32000
        }.merge(options.except(:temperature, :max_tokens))

        client = OpenRouter::Client.new

        # Log the full request being sent
        Rails.logger.info "🚀 OpenRouter Structured Output Request:"
        Rails.logger.info "   Model: #{model_to_use}"
        Rails.logger.info "   Response format: #{response_format.name}"
        Rails.logger.info "   Extras: #{extras.inspect}"

        response = client.complete(
          messages,
          model: model_to_use,
          response_format: response_format,
          extras: extras
        )

        Rails.logger.info "📥 OpenRouter Response:"
        Rails.logger.info "   Content: #{response.content&.truncate(200)}"
        Rails.logger.info "   Model: #{response.model}"
        Rails.logger.info "   Usage: #{response.usage}"
        Rails.logger.info "   Structured output available: #{response.structured_output.present?}"

        response

      rescue StandardError => e
        Rails.logger.error "❌ LLM call failed: #{e.message}"
        Rails.logger.error "🔍 Backtrace: #{e.backtrace.first(3).join("\n")}"

        # Return a mock response with error info
        OpenStruct.new(
          content: "I'm having trouble thinking right now. Please try again.",
          structured_output: nil,
          usage: { prompt_tokens: 0, completion_tokens: 0 },
          model: model_to_use,
          error: e.message
        )
      end
    end

    # Background LLM calls for various purposes (no tools)
    def background_call(prompt:, context: {}, model: nil, **options)
      model_to_use = model || Rails.configuration.default_ai_model

      Rails.logger.info "🧠 Background LLM call: #{model_to_use}"
      Rails.logger.debug "📝 Prompt: #{prompt.first(100)}..."

      # Build messages for background call
      messages = build_background_messages(prompt, context)

      begin
        client = OpenRouter::Client.new
        extras = {
          temperature: options[:temperature] || 0.3,
          max_tokens: options[:max_tokens] || 5000
        }.merge(options.except(:temperature, :max_tokens))

        response = client.complete(
          messages,
          model: model_to_use,
          extras: extras
        )

        Rails.logger.info "✅ Background LLM response received"

        # Extract just the content for background calls
        extract_content_from_response(response)

      rescue StandardError => e
        Rails.logger.error "❌ Background LLM call failed: #{e.message}"
        "Error: Unable to process request"
      end
    end

    # Convenience method for simple text generation
    def generate_text(prompt:, system_prompt: nil, model: nil, **options)
      messages = []

      if system_prompt
        messages << { role: "system", content: system_prompt }
      end

      messages << { role: "user", content: prompt }

      background_call(
        prompt: prompt,
        context: { messages: messages },
        model: model,
        **options
      )
    end

    # Check if LLM service is configured and available
    def available?
      OpenRouter.configured?
    end

    private


    def transform_openrouter_response(response, model)
      return nil unless response

      choice = response.dig("choices", 0)
      message = choice&.dig("message")

      {
        content: message&.dig("content") || "",
        tool_calls: extract_tool_calls(message),
        usage: response["usage"] || { prompt_tokens: 0, completion_tokens: 0 },
        model: model,
        finish_reason: choice&.dig("finish_reason"),
        raw_response: response
      }
    end

    def extract_tool_calls(message)
      return [] unless message&.dig("tool_calls")

      message["tool_calls"].map do |tool_call|
        OpenStruct.new(
          name: tool_call.dig("function", "name"),
          arguments: parse_tool_arguments(tool_call.dig("function", "arguments")),
          id: tool_call["id"]
        )
      end
    end

    def parse_tool_arguments(arguments_string)
      return {} unless arguments_string

      JSON.parse(arguments_string)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse tool arguments: #{e.message}"
      {}
    end

    def build_background_messages(prompt, context)
      # If context includes pre-built messages, use them
      return context[:messages] if context[:messages]

      messages = []

      # Add system message if provided
      if context[:system_prompt]
        messages << { role: "system", content: context[:system_prompt] }
      end

      # Add user prompt
      messages << { role: "user", content: prompt }

      messages
    end

    def extract_content_from_response(response)
      return "No response" unless response

      response.dig("choices", 0, "message", "content") || "Empty response"
    end
  end
end
