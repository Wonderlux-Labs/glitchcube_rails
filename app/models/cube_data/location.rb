# frozen_string_literal: true

class CubeData::Location < CubeData
  class << self
    # Update current location
    def update_location(lat, lng, location_name, accuracy: nil, additional_attrs: {})
      write_sensor(
        sensor_id(:location, :current),
        location_name,
        {
          latitude: lat,
          longitude: lng,
          location_name: location_name,
          accuracy: accuracy,
          last_updated: Time.current.iso8601,
          **additional_attrs
        }
      )

      # Also update individual lat/lng sensors if they exist
      update_coordinate_sensors(lat, lng, accuracy)

      Rails.logger.info "📍 Location updated: #{location_name} (#{lat}, #{lng})"
    end

    # Update location context with landmarks, nearby places, etc.
    def update_context(location_name, landmarks: [], nearby_places: [], additional_info: {})
      write_sensor(
        sensor_id(:location, :context),
        location_name,
        {
          landmarks: landmarks,
          nearby_places: nearby_places,
          last_updated: Time.current.iso8601,
          **additional_info
        }
      )

      Rails.logger.info "🗺️ Location context updated: #{landmarks.count} landmarks"
    end

    # Update proximity information
    def update_proximity(nearby_landmarks, distance_to_landmarks = {})
      closest = distance_to_landmarks.min_by { |_, distance| distance }

      write_sensor(
        sensor_id(:location, :proximity),
        closest&.first || "unknown",
        {
          nearby_landmarks: nearby_landmarks,
          distances: distance_to_landmarks,
          closest_landmark: closest&.first,
          closest_distance: closest&.last,
          last_updated: Time.current.iso8601
        }
      )

      Rails.logger.info "🎯 Proximity updated: #{nearby_landmarks.count} landmarks"
    end

    # Get current location
    def current
      read_sensor(sensor_id(:location, :current))
    end

    # Get location coordinates
    def coordinates
      location = current
      return nil unless location

      lat = location.dig("attributes", "latitude")
      lng = location.dig("attributes", "longitude")

      return nil unless lat && lng

      [ lat.to_f, lng.to_f ]
    end

    # Get current location name
    def current_name
      current&.dig("state")
    end

    # Get location context
    def context
      read_sensor(sensor_id(:location, :context))
    end

    # Get context attribute (landmarks, nearby places, etc.)
    def context_attribute(attribute)
      context_data = context
      context_data&.dig("attributes", attribute)
    end

    # Get nearby landmarks
    def landmarks
      context_attribute("landmarks") || []
    end

    # Get proximity info
    def proximity
      read_sensor(sensor_id(:location, :proximity))
    end

    # Get closest landmark
    def closest_landmark
      proximity&.dig("attributes", "closest_landmark")
    end

    # Get distance to closest landmark
    def closest_distance
      proximity&.dig("attributes", "closest_distance")
    end

    # Check if location data is recent
    def location_fresh?(max_age = 10.minutes)
      location = current
      return false unless location

      timestamp = location.dig("attributes", "last_updated")
      return false unless timestamp

      Time.parse(timestamp) > max_age.ago
    rescue
      false
    end

    # Get location accuracy
    def accuracy
      current&.dig("attributes", "accuracy")&.to_f
    end

    # Check if location is accurate enough for operations
    def accurate_enough?(min_accuracy = 100)
      acc = accuracy
      return false unless acc

      acc <= min_accuracy
    end

    # Extended location string (like HaDataSync.extended_location)
    def extended_location_string
      context_data = context
      return "Location unavailable" unless context_data

      location_name = context_data.dig("state")
      landmarks = context_attribute("landmarks") || []
      porto_distance = context_attribute("porto_distance")

      string = "thE gLitcH cUbe is at - #{location_name}"
      string += "\n nearest landmarks: #{landmarks.join(', ')}" if landmarks.any?

      if porto_distance
        minutes = (porto_distance / 100.0).round(1)
        string += "\n the nearest porto is #{minutes} minute walk away"
      end

      string
    end

    private

    # Update individual coordinate sensors if they exist
    def update_coordinate_sensors(lat, lng, accuracy)
      if sensor_exists?(:location, :latitude)
        write_sensor(sensor_id(:location, :latitude), lat, { last_updated: Time.current.iso8601 })
      end

      if sensor_exists?(:location, :longitude)
        write_sensor(sensor_id(:location, :longitude), lng, { last_updated: Time.current.iso8601 })
      end

      if accuracy && sensor_exists?(:location, :accuracy)
        write_sensor(sensor_id(:location, :accuracy), accuracy, { last_updated: Time.current.iso8601 })
      end
    end
  end
end
