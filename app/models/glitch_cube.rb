# frozen_string_literal: true

# Configuration class for GlitchCube system
# Provides centralized access to configuration values and utility methods
class GlitchCube
  class << self
    def config
      Rails.application.configuration
    end

    def set_random_location
      Services::Gps::GPSTrackingService.new.set_location
    end

    # Set current location for testing/spoofing (console use)
    def set_current_location(lat:, lng:)
      Services::Gps::GPSTrackingService.new.set_location(coords: "#{lat}, #{lng}")
    end

    def home_camp_coordinates
      {}
    end

    def gps_spoofing_allowed?
      return false unless Rails.env.development?

      true
    end
  end
end
