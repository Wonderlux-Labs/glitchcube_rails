# app/jobs/weather_forecast_summarizer_job.rb

class WeatherForecastSummarizerJob < ApplicationJob
  queue_as :default
  
  def perform
    return unless Rails.env.production? || Rails.env.development?
    
    Rails.logger.info "🌤️ WeatherForecastSummarizerJob starting"
    
    WorldStateUpdaters::WeatherForecastSummarizerService.call
    
    Rails.logger.info "✅ WeatherForecastSummarizerJob completed successfully"
    
    # Schedule next run in 1 hour
    self.class.set(wait: 1.hour).perform_later
  rescue StandardError => e
    Rails.logger.error "❌ WeatherForecastSummarizerJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    # Still schedule next run even if this one failed
    self.class.set(wait: 1.hour).perform_later
    # Don't re-raise - we don't want to break the job queue
  end

  # Schedule this job to run every hour
  def self.schedule_repeating
    # Only schedule if using a job processor that supports cron (like sidekiq-cron)
    if defined?(Sidekiq::Cron::Job)
      Sidekiq::Cron::Job.create(
        name: 'Weather Forecast Summarizer',
        cron: '0 * * * *', # Every hour on the hour
        class: 'WeatherForecastSummarizerJob'
      )
    else
      # Fallback for basic ActiveJob - start the recurring chain
      perform_later
    end
  end
end