# frozen_string_literal: true

# Summarizes an outgoing persona's stint when the persona switches
# (enqueued from PersonaSwitchService). Not recurring — event-driven.
class PersonaSummarizerJob < ApplicationJob
  queue_as :default

  def perform(persona_slug)
    result = PersonaSummarizerService.call(persona_slug)

    if result.success?
      data = result.data
      if data[:skipped]
        Rails.logger.info "🎭 PersonaSummarizerJob(#{persona_slug}) skipped: #{data[:reason]}"
      else
        Rails.logger.info "🎭 PersonaSummarizerJob(#{persona_slug}) wrote Summary ##{data[:summary].id}"
      end
    else
      Rails.logger.error "🎭 PersonaSummarizerJob(#{persona_slug}) failed: #{result.error}"
    end
  end
end
