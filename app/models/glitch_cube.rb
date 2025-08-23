# frozen_string_literal: true

# Configuration class for GlitchCube system
# Provides centralized access to configuration values and utility methods
class GlitchCube
  class << self
    def config
      Rails.application.configuration
    end

    def set_random_location
      Gps::GPSTrackingService.new.set_location
    end

    # Set current location for testing/spoofing (console use)
    def set_current_location(lat:, lng:)
      Gps::GPSTrackingService.new.set_location(coords: "#{lat}, #{lng}")
    end

    def home_camp_coordinates
      {}
    end

    def gps_spoofing_allowed?
      return false unless Rails.env.development?

      true
    end

    # Get home camp coordinates (default to center of Black Rock City)
    def home_camp_coordinates
      {
        lat: 40.7864,
        lng: -119.2065,
        address: "Center Camp Plaza",
        name: "Glitch Cube Home Camp"
      }
    end
  end
end
