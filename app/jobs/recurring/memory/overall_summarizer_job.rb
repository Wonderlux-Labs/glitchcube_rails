# frozen_string_literal: true

module Recurring
  module Memory
    # Folds the rolling interaction summaries into the single evolving `overall`
    # summary (OverallSummarizerService). Runs hourly; also triggered manually
    # during testing. Registered in config/recurring.yml.
    class OverallSummarizerJob < ApplicationJob
      queue_as :default

      def perform
        result = OverallSummarizerService.call

        if result.success?
          data = result.data
          if data[:skipped]
            Rails.logger.info "🧠 OverallSummarizerJob skipped: #{data[:reason]}"
          else
            Rails.logger.info "🧠 OverallSummarizerJob folded #{data[:folded]} summaries into Summary ##{data[:summary].id}"
          end
        else
          Rails.logger.error "🧠 OverallSummarizerJob failed: #{result.error}"
        end
      end
    end
  end
end
