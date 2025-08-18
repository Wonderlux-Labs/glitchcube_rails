# frozen_string_literal: true

# Configuration class for GlitchCube system
# Provides centralized access to configuration values and utility methods
class GlitchCube
  class << self
    # GPS and location configuration
    def gps_spoofing_allowed?
      Rails.env.development? || Rails.env.test?
    end

    # Default Burning Man coordinates (The Man)
    def home_camp_coordinates
      {
        lat: 40.7864,
        lng: -119.2065,
        name: "The Man",
        zone: "center"
      }
    end

    # Set current location for testing/spoofing (console use)
    def set_current_location(lat:, lng:)
      return unless gps_spoofing_allowed?

      location_data = {
        lat: lat.to_f,
        lng: lng.to_f,
        timestamp: Time.now.iso8601,
        source: 'spoofed'
      }

      Rails.cache.write('current_cube_location', location_data.to_json, expires_in: 1.hour)
      location_data
    end

    # Get current spoofed location
    def current_spoofed_location
      return nil unless gps_spoofing_allowed?

      cached_data = Rails.cache.read('current_cube_location')
      return nil unless cached_data

      JSON.parse(cached_data, symbolize_names: true)
    rescue JSON::ParserError
      nil
    end

    # Clear spoofed location
    def clear_current_location
      Rails.cache.delete('current_cube_location')
    end

    # Check if location is spoofed
    def location_spoofed?
      gps_spoofing_allowed? && current_spoofed_location.present?
    end
  end
end