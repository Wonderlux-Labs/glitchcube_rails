# frozen_string_literal: true

module Jobs
  class DailySummaryJob < BaseJob
    sidekiq_options queue: "summaries", retry: 3

    def perform
      return unless should_run?

      hourly_summaries = fetch_hourly_summaries
      return if hourly_summaries.empty?

      summary_content = generate_daily_summary(hourly_summaries)
      save_summary(summary_content, "daily")
    rescue StandardError => e
      Services::Logging::SimpleLogger.error "DailySummaryJob failed: #{e.message}"
      raise
    end

    private

    def should_run?
      last_summary = Summary.where(summary_type: "daily")
                            .where("created_at > ?", 1.day.ago)
                            .exists?
      !last_summary
    end

    def fetch_hourly_summaries
      Summary.hourly
             .where(created_at: 24.hours.ago..Time.current)
             .order(created_at: :asc)
    end

    def generate_daily_summary(summaries)
      return "No hourly summaries available for daily consolidation." if summaries.empty?

      summaries_by_type = summaries.group_by(&:summary_type)

      combined_content = summaries_by_type.map do |type, type_summaries|
        content = type_summaries.map do |summary|
          "#{summary.created_at.strftime('%H:%M')}: #{summary.content}"
        end.join("\n")

        "#{type.capitalize} summaries:\n#{content}"
      end.join("\n\n")

      system_prompt = <<~PROMPT
        You are consolidating 24 hourly summaries into a comprehensive daily summary.
        Create a 2-3 paragraph summary that captures:

        1. Overall arc of the day - energy levels, persona effectiveness, major patterns
        2. Most significant interactions and discoveries - memorable moments, breakthroughs, challenges
        3. Key insights and learnings - what worked, what didn't, what to remember

        Write in first person as the cube reflecting on its day.
        Be specific about important events while showing the progression through the day.
        Highlight patterns that emerged across multiple hours.
      PROMPT

      user_message = "Hourly summaries from the past 24 hours:\n\n#{combined_content}"

      response = Services::Llm::LLMService.complete(
        system_prompt: system_prompt,
        user_message: user_message,
        max_tokens: 500,
        temperature: 0.7
      )

      response.content
    end

    def save_summary(content, _type)
      Summary.create!(
        summary_type: "daily",
        period: "daily",
        content: content,
        metadata: {
          hourly_summary_count: fetch_hourly_summaries.count,
          generated_at: Time.current,
          summary_types_included: fetch_hourly_summaries.pluck(:summary_type).uniq
        }
      )
    end
  end
end
