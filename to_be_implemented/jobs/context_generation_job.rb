# frozen_string_literal: true

require 'sidekiq'

module Jobs
  class ContextGenerationJob
    include Sidekiq::Worker

    def perform(model:, prompt:, sensor:, attribute:)
      # Simple LLM call
      response = Services::Llm::LLMService.complete_cheap_no_tools(
        prompt,
        model: model,
        max_tokens: 100,  # Keep it concise
        temperature: 0.3  # Factual summaries
      )

      summary = response.content&.strip

      # Truncate to 255 chars if needed (for main state)
      summary = truncate_intelligently(summary, 255)

      # Initialize HA client
      ha_client = Services::Core::HomeAssistantClient.new

      # Update HA sensor
      if attribute == 'state'
        # Main state value
        ha_client.set_state(sensor, summary)
      else
        # Update as attribute
        ha_client.set_state_attribute(sensor, attribute, summary)
      end
    rescue StandardError => e
      puts "Context generation failed: #{e.message}"
      # Set error state so HA knows
      ha_client ||= Services::Core::HomeAssistantClient.new
      ha_client.set_state_attribute(sensor, "#{attribute}_error", e.message[0..100])
    end

    private

    def truncate_intelligently(text, max_length)
      return text if text.length <= max_length

      # Try to break at sentence
      truncated = text[0..(max_length - 4)]
      last_period = truncated.rindex('.')

      if last_period && last_period > (max_length * 0.7)
        truncated[0..last_period]
      else
        "#{truncated}..."
      end
    end
  end
end
