# frozen_string_literal: true

# ============================================================
# DORMANT — NOT USED IN THE CURRENT (REGIONAL) ITERATION
# GPS/movement disabled for the stationary install; no-op stub, not scheduled in recurring.yml. Restore for a future Burn.
# ============================================================
class Recurring::System::MovementSimulationJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.debug "MovementSimulationJob skipped — GPS disabled for stationary deployment"
  end
end
