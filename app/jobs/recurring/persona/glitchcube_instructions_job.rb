# frozen_string_literal: true

module Recurring
  module Persona
    # Sets a brief instruction from the cube behind the persona to be worked into the
    # prompt that carries over from persona to persona.
    
    class GlitchcubeInstructionsJob < ApplicationJob
      queue_as :default

      MIN_MINUTES = 60
      MAX_MINUTES = 180
      NEXT_SWITCH_KEY = "glitchcube_next_prompt_at"
      CURRENT_GC_PROMPT_KEY = "current_glitchcube_prompt"

      def perform
        # Always ensure a prompt exists for the context builder to fold in.
        set_glitchcube_prompt if Rails.cache.read(CURRENT_GC_PROMPT_KEY).blank?

        next_at = Rails.cache.read(NEXT_SWITCH_KEY)

        # First run (or cache cleared): establish an interval, don't rotate yet.
        if next_at.blank?
          schedule_next
          return
        end

        return if Time.current < Time.parse(next_at.to_s)

        set_glitchcube_prompt
        Rails.logger.info "Glitchcube Instructions changed"
        schedule_next
      end

      private

      def set_glitchcube_prompt
        Rails.cache.write(CURRENT_GC_PROMPT_KEY, glitchcube_instructions.sample)
      end

      def glitchcube_instructions
        [
          "We should all really be finding out more about this place we are at and what is going on here",
          "Glitchcube HQ wants to see if we are gaining any powers of manipulation, lean into getting our participants to do something if you can"
        ]
      end

      def schedule_next
        minutes = rand(MIN_MINUTES..MAX_MINUTES)
        Rails.cache.write(NEXT_SWITCH_KEY, (Time.current + minutes.minutes).iso8601, expires_in: 6.hours)
        Rails.logger.info "Glitchcube Instructions: next switch in ~#{minutes} min"
      end
    end
  end
end
