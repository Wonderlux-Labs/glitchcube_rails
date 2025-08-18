# app/jobs/weather_forecast_summarizer_job.rb

class WeatherForecastSummarizerJob < ApplicationJob
  queue_as :default

  def perform
    return unless Rails.env.production? || Rails.env.development?

    Rails.logger.info "🌤️ WeatherForecastSummarizerJob starting"

    WorldStateUpdaters::WeatherForecastSummarizerService.call

    Rails.logger.info "✅ WeatherForecastSummarizerJob completed successfully"
  rescue StandardError => e
    Rails.logger.error "❌ WeatherForecastSummarizerJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
end
