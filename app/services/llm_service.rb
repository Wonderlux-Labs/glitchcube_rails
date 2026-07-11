# app/services/llm_service.rb
require "ostruct"
require "net/http"
require "timeout"
require "base64"

class LlmService
  # Reliable structured-output models to fall back to when the primary model
  # times out OR comes back empty/unparsable (see call_with_structured_output).
  FAST_FALLBACK_MODELS = [ "google/gemini-3.1-flash-lite", "google/gemini-2.5-flash" ].freeze

  class << self
    # Main conversation call with tool support
    def call_with_tools(messages:, tools: [], model: nil, **options)
      # Respect an explicitly requested model (e.g. the translator pins a
      # precise tool-calling model); only sample from the pool when none given.
      default_pool = [ "mistralai/mistral-medium-3.1", "anthropic/claude-4-sonnet", "google/gemini-2.5-flash", "meta-llama/llama-4-maverick" ]
      # In test env, skip pool sampling so VCR cassettes stay stable
      model_to_use = model || (Rails.env.test? ? nil : default_pool.sample) || Rails.configuration.ai_model

      tool_names = tools.map { |t| t.is_a?(Hash) ? (t.dig(:function, :name) || t.dig("function", "name")) : t.name }
      Rails.logger.info "🤖 LLM call with tools: #{model_to_use} (#{tools.length} tools)"
      Rails.logger.debug { "   tools: #{tool_names.join(', ')} | last msg: #{messages.last&.dig(:content)&.first(200)}" }

      begin
        # Prepare extras with OpenRouter-specific parameters.
        # We do NOT set max_tokens — it's an optional completion cap and, on
        # reasoning models, it's spent on reasoning tokens and starves the actual
        # answer. Leave it unset so each provider uses its own (model-max) default.
        # A caller can still pass one explicitly.
        extras = { temperature: options[:temperature] || 0.9 }
        extras[:max_tokens] = options[:max_tokens] if options[:max_tokens]
        extras.merge!(options.except(:temperature, :max_tokens))

        client = OpenRouter::Client.new

        response = client.complete(
          messages,
          model: model_to_use,
          tools: tools, # Pass tools directly, no serialization needed
          tool_choice: tools.any? ? "auto" : nil,
          extras: extras
        )

        tool_call_count = response.tool_calls&.length || 0
        Rails.logger.info "✅ LLM response: #{response.model} | #{tool_call_count} tool calls | usage=#{response.usage}"
        Rails.logger.debug { "   content: #{response.content&.first(300)}" }
        if response.tool_calls&.any?
          response.tool_calls.each_with_index do |tc, i|
            begin
              Rails.logger.debug { "   tool[#{i + 1}] #{tc.name}: #{tc.arguments}" }
            rescue OpenRouter::ToolCallError => e
              Rails.logger.warn "⚠️  tool[#{i + 1}] #{tc.name}: MALFORMED ARGUMENTS - #{e.message}"
            end
          end
        end

        # Return the actual OpenRouter response object
        response

      rescue Net::ReadTimeout, Timeout::Error => e
        Rails.logger.warn "⏰ LLM tool call timed out with #{model_to_use} (#{e.class}); trying fast models"

        # Try faster models for tool calls on timeout
        fast_models = [ "google/gemini-3.1-flash-lite", "google/gemini-2.5-flash" ]

        fast_models.each do |fast_model|
          begin
            client = OpenRouter::Client.new
            response = client.complete(
              messages,
              model: fast_model,
              tools: tools,
              tool_choice: tools.any? ? "auto" : nil,
              extras: extras
            )

            Rails.logger.info "✅ Fast model #{fast_model} recovered the tool call after timeout"
            return response
          rescue => fallback_error
            Rails.logger.warn "❌ Fast model #{fast_model} failed: #{fallback_error.message}"
            next
          end
        end

        Rails.logger.error "💥 All fast models failed for tool call timeout"
        OpenStruct.new(
          content: "I'm having trouble thinking right now. Please try again.",
          tool_calls: [],
          has_tool_calls?: false,
          usage: { prompt_tokens: 0, completion_tokens: 0 },
          model: model_to_use,
          error: "All models timed out"
        )

      rescue StandardError => e
        Rails.logger.error "❌ LLM tool call failed with #{model_to_use}: #{e.class} - #{e.message}"
        Rails.logger.debug { e.backtrace.first(5).join("\n") }

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
      default_pool = [ "mistralai/mistral-medium-3.1", "anthropic/claude-4-sonnet", "google/gemini-2.5-flash", "meta-llama/llama-4-maverick" ]
      # In test env, skip pool sampling so VCR cassettes stay stable
      model_to_use = model || (Rails.env.test? ? nil : default_pool.sample) || Rails.configuration.ai_model

      Rails.logger.info "🤖 LLM structured-output call: #{model_to_use} (#{response_format.name})"
      Rails.logger.debug { "   last msg: #{messages.last&.dig(:content)&.first(200)}" }

      begin
        # Prepare extras with OpenRouter-specific parameters.
        # We do NOT set max_tokens. It's an optional completion cap; on reasoning
        # models the reasoning tokens eat the cap and the structured answer comes
        # back empty (finish_reason "stop", content ""), which we'd misread as a
        # failure. Leave it unset so each provider uses its own (model-max) default.
        # A caller can still pass one explicitly.
        extras = { temperature: options[:temperature] || 0.9 }
        extras[:max_tokens] = options[:max_tokens] if options[:max_tokens]
        extras.merge!(options.except(:temperature, :max_tokens))

        client = OpenRouter::Client.new

        response = client.complete(
          messages,
          model: model_to_use,
          response_format: response_format,
          extras: extras
        )

        u = response.usage || {}
        Rails.logger.info "✅ LLM response: #{response.model} | structured=#{response.structured_output.present?} | " \
                          "tokens prompt=#{u['prompt_tokens']} completion=#{u['completion_tokens']} total=#{u['total_tokens']} | " \
                          "cost=$#{u['cost']}"
        Rails.logger.debug { "   content: #{response.content&.truncate(300)}" }

        # A "successful" call can still come back with empty/unparsable content — some
        # providers occasionally return finish_reason "stop" with a blank or truncated
        # body, which yields no structured output and no exception. That's not a timeout,
        # so it never hit the rescue below and used to fall straight through to the
        # caller's degraded fallback. Instead, silently resend to a reliable secondary
        # model (no TTS filler — the visitor never hears the retry).
        if response.structured_output.blank?
          Rails.logger.warn "⚠️ #{response.model || model_to_use} returned no parseable structured output " \
                             "(content=#{response.content.to_s.length} chars); retrying on secondary model(s)"
          recovered = retry_structured_on_secondary(messages, response_format, extras, exclude: model_to_use)
          return recovered if recovered
        end

        response

      rescue Net::ReadTimeout, Timeout::Error => e
        Rails.logger.warn "⏰ LLM call timed out with #{model_to_use} (#{e.class}); trying fast fallback models"

        FAST_FALLBACK_MODELS.each do |fallback_model|
          begin
            response = attempt_structured_output_call(messages, response_format, fallback_model, extras)
            Rails.logger.info "✅ Fast fallback model #{fallback_model} recovered after timeout"
            return response
          rescue => fallback_error
            Rails.logger.warn "❌ Fast fallback model #{fallback_model} failed: #{fallback_error.message}"
            next
          end
        end

        Rails.logger.error "💥 All fast fallback models failed after timeout"
        OpenStruct.new(
          content: "I'm having trouble thinking right now. Please try again.",
          structured_output: nil,
          usage: { prompt_tokens: 0, completion_tokens: 0 },
          model: model_to_use,
          error: "All models timed out"
        )

      rescue StandardError => e
        Rails.logger.error "❌ LLM structured-output call failed with #{model_to_use}: #{e.class} - #{e.message}"
        Rails.logger.debug { e.backtrace.first(5).join("\n") }

        # A hard error (bad model id, 429, provider 5xx) shouldn't cost us the whole call —
        # try a reliable secondary before giving up, so one flaky/misconfigured model never
        # silently drops a summary or a turn.
        recovered = retry_structured_on_secondary(messages, response_format, extras, exclude: model_to_use)
        return recovered if recovered

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

    private

    def attempt_structured_output_call(messages, response_format, model, extras)
      client = OpenRouter::Client.new
      client.complete(
        messages,
        model: model,
        response_format: response_format,
        extras: extras
      )
    end

    # Resend the same request to reliable secondary models, returning the first
    # response that actually parses into structured output. nil if none recover.
    def retry_structured_on_secondary(messages, response_format, extras, exclude:)
      (FAST_FALLBACK_MODELS - [ exclude ]).each do |model|
        begin
          resp = attempt_structured_output_call(messages, response_format, model, extras)
          if resp.structured_output.present?
            Rails.logger.info "✅ Secondary #{model} recovered structured output after empty primary response"
            return resp
          end
          Rails.logger.warn "⚠️ Secondary #{model} also returned empty structured output"
        rescue => e
          Rails.logger.warn "❌ Secondary #{model} failed: #{e.message}"
        end
      end
      nil
    end

    public

    # Background LLM calls for various purposes (no tools)
    def background_call(prompt:, context: {}, model: nil, **options)
      model_to_use = model || Rails.configuration.ai_model

      Rails.logger.info "🧠 Background LLM call: #{model_to_use}"
      Rails.logger.debug "📝 Prompt: #{prompt.first(100)}..."

      # Build messages for background call
      messages = build_background_messages(prompt, context)

      begin
        client = OpenRouter::Client.new
        # max_tokens left unset (see note in call_with_structured_output).
        extras = { temperature: options[:temperature] || 0.3 }
        extras[:max_tokens] = options[:max_tokens] if options[:max_tokens]
        extras.merge!(options.except(:temperature, :max_tokens))

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

    # One-shot vision call: send an image (base64 data-URI content part) plus a prompt
    # to a vision-capable model and return the text reply. If the primary raises or
    # comes back blank, retry once on the configured fallback model (same idea as
    # retry_structured_on_secondary), then raise — the caller (CameraDescriptionJob)
    # wants a loud failure, not a degraded description.
    def call_with_vision(prompt:, image_path:, model: nil)
      model_to_use = model || Rails.configuration.camera_vision_model
      messages = vision_messages(prompt, image_path)

      Rails.logger.info "👁️ LLM vision call: #{model_to_use} (#{File.basename(image_path)})"

      begin
        content = attempt_vision_call(messages, model_to_use)
        return content if content.present?
        Rails.logger.warn "⚠️ #{model_to_use} returned an empty vision response; retrying on fallback"
      rescue StandardError => e
        Rails.logger.warn "❌ Vision call failed on #{model_to_use}: #{e.message}; retrying on fallback"
      end

      fallback_model = Rails.configuration.vision_fallback_model
      content = attempt_vision_call(messages, fallback_model)
      raise "Vision call returned no content on #{model_to_use} or #{fallback_model}" if content.blank?

      Rails.logger.info "✅ Vision fallback #{fallback_model} recovered"
      content
    end

    # Check if LLM service is configured and available
    def available?
      OpenRouter.configuration.access_token.present?
    end

    private

    def vision_messages(prompt, image_path)
      image_uri = "data:image/jpeg;base64,#{Base64.strict_encode64(File.binread(image_path))}"
      [ {
        role: "user",
        content: [
          { type: "text", text: prompt },
          { type: "image_url", image_url: { url: image_uri } }
        ]
      } ]
    end

    def attempt_vision_call(messages, model)
      client = OpenRouter::Client.new
      response = client.complete(messages, model: model, extras: { temperature: 0.3 })
      response.content
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
