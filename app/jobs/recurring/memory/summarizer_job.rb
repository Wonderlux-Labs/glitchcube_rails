# frozen_string_literal: true

module Recurring
  module Memory
    # Write a factual interaction CHUNK for one persona's current stint
    # (SummarizerService). Enqueued per-persona every ~N turns by SummaryTriggers —
    # no longer a cron job.
    class SummarizerJob < ApplicationJob
      queue_as :default

      def perform(persona_slug)
        result = SummarizerService.call(persona_slug)

        if result.success?
          data = result.data
          if data[:skipped]
            Rails.logger.info "📝 SummarizerJob(#{persona_slug}) skipped: #{data[:reason]}"
          else
            Rails.logger.info "📝 SummarizerJob(#{persona_slug}) wrote Summary ##{data[:summary].id}"
          end
        else
          Rails.logger.error "📝 SummarizerJob(#{persona_slug}) failed: #{result.error}"
        end
      end
    end
  end
end
