# frozen_string_literal: true

module Jobs
  class EventMemorySummarizerJob < BaseJob
    sidekiq_options queue: 'summaries', retry: 3

    def perform
      return unless should_run?

      recent_conversations = fetch_recent_conversations
      return if recent_conversations.empty?

      summary_content = generate_event_summary(recent_conversations)
      save_summary(summary_content, 'event')
    rescue StandardError => e
      Services::Logging::SimpleLogger.error "EventMemorySummarizerJob failed: #{e.message}"
      raise
    end

    private

    def should_run?
      # Don't run if we already have a recent summary
      last_summary = Summary.where(summary_type: 'event')
                            .where('created_at > ?', 1.hour.ago)
                            .exists?
      return false if last_summary

      # Don't run if there are no conversations to summarize
      Conversation.where(created_at: 1.hour.ago..Time.current)
                  .joins(:messages)
                  .exists?
    end

    def fetch_recent_conversations
      Conversation.includes(:messages)
                  .where(created_at: 1.hour.ago..Time.current)
                  .where.not(messages: { id: nil })
    end

    def generate_event_summary(conversations)
      return 'No significant events in the past hour.' if conversations.empty?

      all_messages = conversations.flat_map do |conv|
        conv.messages.map do |msg|
          "#{msg.created_at.strftime('%H:%M')} [#{conv.persona || 'unknown'}]: #{msg.content}"
        end
      end.join("\n")

      system_prompt = <<~PROMPT
        You are identifying and summarizing significant moments and memorable events from the past hour.
        Focus on:
        - Unique discoveries (acoustic properties, interference patterns)
        - Meaningful interactions (child asking about dreams, philosophical questions)
        - Technical or environmental events (Tesla coil interference, system behaviors)
        - Consciousness triggers or deep questions
        - Artistic or creative moments (harp in trash can, light patterns)

        Write a 1 paragraph summary of the most significant moments.
        Be specific about what made each moment notable.
        Example style: "Someone played harp in trash can (acoustic discovery), Tesla coil interference created beautiful chaos patterns, child asked about dreams (consciousness trigger)"
      PROMPT

      user_message = "Conversations and events from the past hour:\n#{all_messages}"

      response = Services::Llm::LLMService.complete(
        system_prompt: system_prompt,
        user_message: user_message,
        max_tokens: 200,
        temperature: 0.7
      )

      response.content
    end

    def save_summary(content, type)
      Summary.create!(
        summary_type: type,
        period: 'hourly',
        content: content,
        metadata: {
          conversation_count: fetch_recent_conversations.count,
          generated_at: Time.current
        }
      )
    end
  end
end
