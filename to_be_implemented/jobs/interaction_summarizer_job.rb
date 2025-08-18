# frozen_string_literal: true

module Jobs
  class InteractionSummarizerJob < BaseJob
    sidekiq_options queue: 'summaries', retry: 3

    def perform
      return unless should_run?

      recent_messages = fetch_recent_messages
      return if recent_messages.empty?

      summary_content = generate_interaction_summary(recent_messages)
      save_summary(summary_content, 'interaction')
    rescue StandardError => e
      Services::Logging::SimpleLogger.error "InteractionSummarizerJob failed: #{e.message}"
      raise
    end

    private

    def should_run?
      # Don't run if we already have a recent summary
      last_summary = Summary.where(summary_type: 'interaction')
                            .where('created_at > ?', 1.hour.ago)
                            .exists?
      return false if last_summary

      # Don't run if there are no messages to summarize
      Message.where(created_at: 1.hour.ago..Time.current)
             .where(role: 'user')
             .exists?
    end

    def fetch_recent_messages
      Message.includes(:conversation)
             .where(created_at: 1.hour.ago..Time.current)
             .where(role: 'user')
             .order(created_at: :asc)
    end

    def generate_interaction_summary(messages)
      return 'No human interactions in the past hour.' if messages.empty?

      message_content = messages.map do |msg|
        persona = msg.conversation&.persona || 'unknown'
        "#{msg.created_at.strftime('%H:%M')} [#{persona} mode]: #{msg.content}"
      end.join("\n")

      system_prompt = <<~PROMPT
        You are summarizing social dynamics and human interactions from the past hour.
        Focus on:
        - Different voices and people interacting
        - Topics discussed (ice cream, Bach, synesthesia, etc.)
        - Group dynamics (people talking over each other, excitement levels)
        - Time patterns of interactions
        - Notable questions or requests

        Write a 1 paragraph summary describing the social interactions.
        Be specific about times and group dynamics.
        Example style: "4:10 - excited person asking about ice cream, 4:25 - different voice discussing Bach, 4:40 - group of 3 talking over each other about synesthesia"
      PROMPT

      user_message = "Human interactions from the past hour:\n#{message_content}"

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
          interaction_count: fetch_recent_messages.count,
          generated_at: Time.current
        }
      )
    end
  end
end
