# frozen_string_literal: true

require 'sidekiq'

module Jobs
  # Base class for all Sidekiq jobs
  # Ensures common dependencies are loaded and provides shared functionality
  class BaseJob
    include Sidekiq::Job

    private

    # Provide easy access to logger for all jobs
    def logger
      Services::Logging::SimpleLogger
    end
  end
end
