# frozen_string_literal: true

module Recurring
  module Artifact
    # The daily amnesia loop. Pure arithmetic (no LLM): decays belief confidence and
    # prunes the mundane memory log. Hands off to ArtifactDecayService.
    class DecayJob < ApplicationJob
      queue_as :default

      def perform
        Rails.logger.info "🌫️ DecayJob starting"
        result = ArtifactDecayService.call
        Rails.logger.info(result.success? ? "✅ DecayJob: #{result.data}" : "❌ DecayJob: #{result.error}")
      end
    end
  end
end
