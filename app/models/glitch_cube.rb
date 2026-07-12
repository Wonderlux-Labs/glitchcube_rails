# frozen_string_literal: true

# ============================================================
# DORMANT — NOT USED IN THE CURRENT (REGIONAL) ITERATION
# GPS location spoofing/home-camp helpers; only callers are the GPS/GIS bundle. Restore for a future Burn.
# ============================================================

# Configuration class for GlitchCube system
# Provides centralized access to configuration values and utility methods
class GlitchCube
  class << self
    def config
      Rails.application.configuration
    end

    def set_random_location
      Gps::GpsTrackingService.new.set_location
    end

    # Set current location for testing/spoofing (console use)
    def set_current_location(lat:, lng:)
      Gps::GpsTrackingService.new.set_location(coords: "#{lat}, #{lng}")
    end

    def gps_spoofing_allowed?
      Rails.env.development? || Rails.env.test?
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
