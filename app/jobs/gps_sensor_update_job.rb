# frozen_string_literal: true

# Background job to update Home Assistant with current GPS location
# Runs every 5 minutes to keep the sensor data fresh
class GpsSensorUpdateJob < ApplicationJob
  queue_as :default

  def perform
    return unless Rails.env.production? || Rails.env.development?

    begin
      # Get current location from GPS service
      gps_service = Services::Gps::GPSTrackingService.new
      location_data = gps_service.current_location

      return unless location_data && location_data[:lat] && location_data[:lng]

      # Update Home Assistant sensors
      ha_service = HomeAssistantService.new

      # Update latitude sensor
      ha_service.set_entity_state(
        'sensor.glitchcube_current_latitude',
        location_data[:lat].to_s,
        {
          unit_of_measurement: '°',
          friendly_name: 'GlitchCube Current Latitude',
          device_class: 'distance',
          last_updated: Time.now.iso8601,
          source: location_data[:source] || 'unknown'
        }
      )

      # Update longitude sensor
      ha_service.set_entity_state(
        'sensor.glitchcube_current_longitude',
        location_data[:lng].to_s,
        {
          unit_of_measurement: '°',
          friendly_name: 'GlitchCube Current Longitude',
          device_class: 'distance',
          last_updated: Time.now.iso8601,
          source: location_data[:source] || 'unknown'
        }
      )

      # Update location context sensor
      ha_service.set_entity_state(
        'sensor.glitchcube_location_context',
        location_data[:address] || location_data[:zone]&.to_s&.humanize || 'Unknown',
        {
          friendly_name: 'GlitchCube Location Context',
          zone: location_data[:zone],
          address: location_data[:address],
          within_fence: location_data[:within_fence],
          distance_from_man: location_data[:distance_from_man],
          last_updated: Time.now.iso8601,
          landmarks: location_data[:landmarks]&.first(3)&.map { |l| l[:name] }&.join(', ')
        }
      )

      Rails.logger.info "GPS sensor update completed successfully"
    rescue StandardError => e
      Rails.logger.error "GPS sensor update failed: #{e.message}"
      # Don't re-raise - we don't want to break the job queue
    end
  end

  # Schedule this job to run every 5 minutes
  def self.schedule_repeating
    # Only schedule if using a job processor that supports cron (like sidekiq-cron)
    if defined?(Sidekiq::Cron::Job)
      Sidekiq::Cron::Job.create(
        name: 'GPS Sensor Update',
        cron: '*/5 * * * *', # Every 5 minutes
        class: 'GpsSensorUpdateJob'
      )
    else
      # Fallback for basic ActiveJob - schedule next run at end of current job
      perform_later
      GpsSensorUpdateJob.set(wait: 5.minutes).perform_later
    end
  end
end