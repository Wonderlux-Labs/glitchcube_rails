# app/jobs/recurring/persona/random_persona_job.rb
require "mission_control/jobs" if defined?(Rails)

module Recurring
  module Persona
    class RandomPersonaJob < ApplicationJob
      queue_as :default

      def perform
        if rand(1..100) > 50
          Rails.logger.info "🎲 RandomPersonaJob: Skipping persona change (random check failed)"
        else
          Rails.logger.info "🎲 RandomPersonaJob: Triggering random persona change"
          CubePersona.set_random
        end
      end
    end
  end
end
