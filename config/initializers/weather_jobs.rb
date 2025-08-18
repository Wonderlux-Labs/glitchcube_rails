# frozen_string_literal: true

# Weather job initialization
# This starts the recurring weather forecast summarizer job

Rails.application.configure do
  # Start weather forecast summarizer job in production and development
  # Skip in test environment
  if Rails.env.production? || Rails.env.development?
    config.after_initialize do
      # Start the weather forecast summarizer job
      WeatherForecastSummarizerJob.set(wait: 1.minute).perform_later
    end
  end
end