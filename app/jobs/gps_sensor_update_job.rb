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

      # Update Home Assistant location context sensor only
      # (GPS coordinates come from HA device tracker)
      ha_service = HomeAssistantService.new

      # Create location context sensor with enriched data
      ha_service.set_entity_state(
        'sensor.glitchcube_location_context',
        location_data[:address] || location_data[:zone]&.to_s&.humanize || 'Unknown',
        {
          friendly_name: 'GlitchCube Location Context',
          icon: 'mdi:map-marker-radius',
          
          # Location details
          zone: location_data[:zone],
          address: location_data[:address],
          street: location_data[:street],
          block: location_data[:block],
          
          # Geofencing
          within_fence: location_data[:within_fence],
          distance_from_man: location_data[:distance_from_man],
          
          # Landmarks and POIs
          landmarks: location_data[:landmarks]&.first(5)&.map { |l| l[:name] }&.join(', '),
          landmark_count: location_data[:landmarks]&.count || 0,
          nearest_landmark: location_data[:landmarks]&.first&.[](:name),
          
          # Porto info
          nearest_porto: location_data[:nearest_porto]&.[](:name),
          porto_distance: location_data[:nearest_porto]&.[](:distance_meters),
          
          # Metadata
          coordinates: "#{location_data[:lat]}, #{location_data[:lng]}",
          source: location_data[:source] || 'home_assistant',
          last_updated: Time.now.iso8601
        }
      )

      Rails.logger.info "GPS sensor update completed successfully"
    rescue StandardError => e
      Rails.logger.error "GPS sensor update failed: #{e.message}"
      # Don't re-raise - we don't want to break the job queue
    end
  end

end