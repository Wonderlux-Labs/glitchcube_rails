# frozen_string_literal: true

# ============================================================
# DORMANT — NOT USED IN THE CURRENT (REGIONAL) ITERATION
# GPS disabled for the stationary install; no-op stub, not scheduled in recurring.yml. Restore for a future Burn.
# ============================================================
module Recurring
  module System
    class GpsSensorUpdateJob < ApplicationJob
      queue_as :default

      def perform
        Rails.logger.debug "GpsSensorUpdateJob skipped — GPS disabled for stationary deployment"
      end
    end
  end
end
