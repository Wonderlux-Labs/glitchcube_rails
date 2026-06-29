# frozen_string_literal: true

# Movement simulation — disabled for stationary regional installation.
# Restore for Burning Man deployment when GPS/movement is needed.
class Recurring::System::MovementSimulationJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.debug "MovementSimulationJob skipped — GPS disabled for stationary deployment"
  end
end
