# frozen_string_literal: true

module Jobs
  class HostRegistrationWorker < BaseJob
    # Run every 5 minutes to ensure registration stays current
    sidekiq_options retry: 3, queue: :default

    def perform(registration_type = nil)
      # Handle both string argument for initial registration and no argument for cron job
      initial_registration = (registration_type == 'initial_registration')

      if initial_registration
        # Try to register with retry loop for initial registration
        Services::Logging::SimpleLogger.info(
          '🚀 Starting initial host registration with Home Assistant',
          tagged: %i[host_registration startup]
        )

        success = Services::System::HostRegistrationService.register_with_retry_loop

        if success
          Services::Logging::SimpleLogger.info(
            '✅ Initial registration successful - regular updates handled by cron job',
            tagged: %i[host_registration startup]
          )
        else
          Services::Logging::SimpleLogger.error(
            '❌ Initial registration failed - will retry via Sidekiq retry mechanism',
            tagged: %i[host_registration startup error]
          )
          raise 'Failed to register with Home Assistant after all attempts'
        end
      else
        # Regular registration update (called by cron job with no arguments)
        Services::Logging::SimpleLogger.debug(
          '🔄 Performing regular host registration update',
          tagged: %i[host_registration cron]
        )

        # This is the regular cron job - just register normally
        success = Services::System::HostRegistrationService.register_with_home_assistant

        if success
          Services::Logging::SimpleLogger.debug(
            '✅ Regular host registration update successful',
            tagged: %i[host_registration cron]
          )
        else
          Services::Logging::SimpleLogger.warn(
            '⚠️ Regular host registration update failed',
            tagged: %i[host_registration cron]
          )
        end
      end
    end
  end
end
