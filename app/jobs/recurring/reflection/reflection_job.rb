# frozen_string_literal: true

module Recurring
  module Reflection
    # Periodic continuity pass. Hands off to ReflectionService, which reads
    # un-reflected conversations, rewrites the world-state, and saves memories.
    class ReflectionJob < ApplicationJob
      queue_as :default

      def perform
        Rails.logger.info "🪞 ReflectionJob starting"
        result = ReflectionService.call
        if result.success?
          Rails.logger.info "✅ ReflectionJob: #{result.data}"
        else
          Rails.logger.error "❌ ReflectionJob: #{result.error}"
        end
      end
    end
  end
end
