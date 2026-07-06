# frozen_string_literal: true

module Recurring
  module Memory
    # Every ~10 minutes: write a rolling "running memory" summary of recent
    # interactions (SummarizerService). Registered in config/recurring.yml.
    class SummarizerJob < ApplicationJob
      queue_as :default

      def perform
        result = SummarizerService.call

        if result.success?
          data = result.data
          if data[:skipped]
            Rails.logger.info "📝 SummarizerJob skipped: #{data[:reason]}"
          else
            Rails.logger.info "📝 SummarizerJob wrote Summary ##{data[:summary].id}"
          end
        else
          Rails.logger.error "📝 SummarizerJob failed: #{result.error}"
        end
      end
    end
  end
end
