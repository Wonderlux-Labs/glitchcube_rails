# frozen_string_literal: true

# GPS job initialization
# This starts the recurring GPS sensor update job

Rails.application.configure do
  # Start GPS sensor update job in production and development
  # Skip in test environment
  if Rails.env.production? || Rails.env.development?
    config.after_initialize do
      # Start the GPS sensor update job
      GpsSensorUpdateJob.set(wait: 1.minute).perform_later
    end
  end
end