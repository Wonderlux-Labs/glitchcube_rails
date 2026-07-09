# frozen_string_literal: true

module Recurring
  module Persona
    # Automatic persona rotation. The cube switches to a random persona once a
    # randomized 30–90 minute interval has elapsed. The job itself runs on a short
    # cadence (see config/recurring.yml) and only acts when the interval is up, so
    # switches feel organic rather than clockwork.
    class RandomPersonaJob < ApplicationJob
      queue_as :default

      MIN_MINUTES = 30
      MAX_MINUTES = 90
      NEXT_SWITCH_KEY = "persona_next_switch_at"

      def perform
        next_at = Rails.cache.read(NEXT_SWITCH_KEY)

        # First run (or cache cleared): establish an interval, don't switch yet.
        if next_at.blank?
          schedule_next
          return
        end

        return if Time.current < Time.parse(next_at.to_s)

        Rails.logger.info "🎲 RandomPersonaJob: interval elapsed, switching persona"
        CubePersona.set_random(entrance: :grand)
        schedule_next
      end

      private

      def schedule_next
        minutes = rand(MIN_MINUTES..MAX_MINUTES)
        Rails.cache.write(NEXT_SWITCH_KEY, (Time.current + minutes.minutes).iso8601, expires_in: 6.hours)
        Rails.logger.info "🎲 RandomPersonaJob: next switch in ~#{minutes} min"
      end
    end
  end
end
