# frozen_string_literal: true

# GPS sensor update — disabled for stationary regional installation.
# Restore for Burning Man deployment when GPS/location services are needed.
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
