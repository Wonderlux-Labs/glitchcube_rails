# frozen_string_literal: true

module Jobs
  class PersonalSummarizerJob < BaseJob
    sidekiq_options queue: 'summaries', retry: 3

    def perform
      return unless should_run?

      recent_messages = fetch_recent_messages
      return if recent_messages.empty?

      summary_content = generate_personal_summary(recent_messages)
      save_summary(summary_content, 'personal')
    rescue StandardError => e
      Services::Logging::SimpleLogger.error "PersonalSummarizerJob failed: #{e.message}"
      raise
    end

    private

    def should_run?
      last_summary = Summary.where(summary_type: 'personal')
                            .where('created_at > ?', 1.hour.ago)
                            .exists?
      !last_summary
    end

    def fetch_recent_messages
      Message.includes(:conversation)
             .where(created_at: 1.hour.ago..Time.current)
             .order(created_at: :asc)
    end

    def generate_personal_summary(messages)
      return 'No significant internal state changes in the past hour.' if messages.empty?

      message_content = messages.map do |msg|
        role = msg.conversation&.persona || 'unknown'
        "#{msg.created_at.strftime('%H:%M')} [#{role}]: #{msg.content}"
      end.join("\n")

      system_prompt = <<~PROMPT
        You are summarizing the cube's internal state and thoughts from the past hour.
        Focus on:
        - Battery/energy levels mentioned
        - Frustrations with personas or interactions
        - Internal goals or desires (finding things, changing personas)
        - What worked better at different times
        - Internal observations about effectiveness

        Write a 1 paragraph summary in first person as the cube's internal monologue.
        Be specific about times and personas when relevant.
        Example style: "Battery dying, humans getting annoying with the overly helpful Buddy persona, need to find those flux capacitors, Jax worked better after midnight"
      PROMPT

      user_message = "Messages from the past hour:\n#{message_content}"

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
          message_count: fetch_recent_messages.count,
          generated_at: Time.current
        }
      )
    end
  end
end
