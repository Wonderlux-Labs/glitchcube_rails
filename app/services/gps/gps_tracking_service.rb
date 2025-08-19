# frozen_string_literal: true

# Simple service to get GPS coordinates from Home Assistant
# All location context comes from LocationContextService
module Services
  module Gps
    class GPSTrackingService
      def initialize
        @ha_service = HomeAssistantService.new
      end

      # Get current GPS coordinates with full location context
      def current_location
        # Use cached location if available (5 minute cache)
        cached = Rails.cache.fetch("gps_current_location", expires_in: 5.minutes) do
          random_landmark_location
        end

        return nil unless cached && cached[:lat] && cached[:lng]

        # Get full context from LocationContextService (this is also cached)
        context = LocationContextService.full_context(cached[:lat], cached[:lng])

        # Merge GPS metadata with location context
        cached.merge(context)
      end

      # Get proximity data for map reactions using LocationContextService
      def proximity_data(lat, lng)
        context = LocationContextService.full_context(lat, lng)
        landmarks = context[:landmarks] || []

        {
          landmarks: landmarks,
          portos: context[:nearest_porto] ? [ context[:nearest_porto] ] : [],
          map_mode: determine_map_mode_from_landmarks(landmarks),
          visual_effects: determine_visual_effects_from_landmarks(landmarks)
        }
      end

      # Deprecated method for backward compatibility
      def brc_address_from_coordinates(lat, lng)
        context = LocationContextService.full_context(lat, lng)
        context[:address]
      end

      # Set location directly (console convenience method)
      def set_location(coords: nil)
        if coords.nil?
          l = Landmark.active.sample
          lat = l.latitude
          lng = l.longitude
        else
          lat = coords.split(",").first.to_f
          lng = coords.split(",").last.to_f
        end

        return false unless GlitchCube.gps_spoofing_allowed?

        location_data = {
          lat: lat.to_f,
          lng: lng.to_f,
          timestamp: Time.now,
          source: "manual_override"
        }

        # Write directly to the main cache
        Rails.cache.write("gps_current_location", location_data, expires_in: 5.minutes)
        true
      end

      # Simulate cube movement - walk toward a landmark and stop when reached
      def simulate_movement!(landmark: nil)
        return unless GlitchCube.gps_spoofing_allowed?

        begin
          # Get current cached location
          current_data = Rails.cache.fetch("gps_current_location") do
            fetch_from_home_assistant
          end

          destination_data = Rails.cache.read("cube_destination")
          destination = if destination_data
                          JSON.parse(destination_data, symbolize_names: true)
          else
                          {
                            lat: landmark.latitude.to_f,
                            lng: landmark.longitude.to_f,
                            name: landmark.name
                          }
          end
          Rails.cache.write("cube_destination", destination.to_json, expires_in: 2.hours)
          puts "Current #{current_data}"
          puts "Dest #{destination}"
          # Check if we've reached the destination
          if reached_destination?(current_data, destination)
            Rails.cache.delete("cube_destination") # Clear destination
            return "Arrived at #{destination[:name]}"
          end

          # Move toward destination (small step)
          new_location = move_toward_destination(current_data, destination)
          set_location(coords: "#{new_location[:lat]},#{new_location[:lng]}")

          distance = calculate_distance(current_data[:lat], current_data[:lng], destination[:lat], destination[:lng])
          puts "Moving toward #{destination[:name]} (#{distance.round}m remaining)"
          sleep(5)
          simulate_movement!(landmark: landmark)
        rescue StandardError => e
          puts e.inspect
          puts e.backtrace.inspect
          "Movement simulation failed: #{e.message}"
        end
      end

      private


      def pick_random_destination
        # Pick a random landmark as destination using PostGIS
        landmark = Landmark.active.order("RANDOM()").first
        {
          lat: landmark.latitude.to_f,
          lng: landmark.longitude.to_f,
          name: landmark.name,
          timestamp: Time.now.iso8601
        }
      end

      def find_nearby_landmarks(lat, lng, radius_meters = 1000)
        # Use PostGIS to find landmarks within radius
        Landmark.within_meters(lng, lat, radius_meters).active
      end

      def reached_destination?(current, destination)
        return unless destination

        # Use PostGIS-based distance calculation
        landmark = Landmark.new(latitude: destination[:lat], longitude: destination[:lng])
        distance = landmark.distance_from(current[:lat], current[:lng]) * 1609.34 # Convert miles to meters
        distance < 50 # Within 50 meters
      end

      def move_toward_destination(current, destination)
        # Use PostGIS-based distance and direction
        current_landmark = Landmark.new(latitude: current[:lat], longitude: current[:lng])
        dest_landmark = Landmark.new(latitude: destination[:lat], longitude: destination[:lng])

        # Calculate distance using PostGIS
        total_distance_meters = current_landmark.distance_from(destination[:lat], destination[:lng]) * 1609.34

        # Step size (about 10-20 meters)
        step_meters = 15

        # Calculate direction vector
        lat_diff = destination[:lat] - current[:lat]
        lng_diff = destination[:lng] - current[:lng]

        # Normalize and scale by step size
        total_distance_deg = Math.sqrt(lat_diff**2 + lng_diff**2)
        return current if total_distance_deg.zero?

        scale_factor = step_meters / total_distance_meters

        new_lat = current[:lat] + (lat_diff * scale_factor)
        new_lng = current[:lng] + (lng_diff * scale_factor)

        {
          lat: new_lat,
          lng: new_lng,
          timestamp: Time.now.iso8601
        }
      end

      def calculate_distance(lat1, lng1, lat2, lng2)
        # Use PostGIS-based distance calculation
        landmark1 = Landmark.new(latitude: lat1, longitude: lng1)
        landmark1.distance_from(lat2, lng2) * 1609.34 # Convert miles to meters
      end

      def determine_map_mode_from_landmarks(landmarks)
        return "normal" if landmarks.empty?

        primary = landmarks.first
        case primary[:type]
        when "sacred" then "temple"
        when "center" then "man"
        when "medical" then "emergency"
        when "service" then "service"
        else "landmark"
        end
      end

      def determine_visual_effects_from_landmarks(landmarks)
        effects = []

        landmarks.each do |landmark|
          case landmark[:type]
          when "sacred"
            effects << { type: "aura", color: "white", intensity: "soft" }
          when "center"
            effects << { type: "pulse", color: "orange", intensity: "strong" }
          when "medical"
            effects << { type: "beacon", color: "red", intensity: "steady" }
          when "service"
            effects << { type: "glow", color: "blue", intensity: "medium" }
          end
        end

        effects
      end

      def fetch_from_home_assistant
        # Get latitude and longitude from the glitchcube sensors
        lat_sensor = @ha_service.entity("sensor.glitchcube_latitude")
        lng_sensor = @ha_service.entity("sensor.glitchcube_longitude")

        return nil unless lat_sensor && lng_sensor

        # Get GPS quality from HTIT tracker
        quality_sensor = @ha_service.entity("sensor.heltec_htit_tracker_gps_quality")
        gps_quality = quality_sensor ? quality_sensor["state"].to_i : nil

        # Get satellite count from HTIT tracker
        sat_sensor = @ha_service.entity("sensor.heltec_htit_tracker_satellites")
        satellites = sat_sensor ? sat_sensor["state"].to_i : nil

        # Get device uptime from HTIT tracker (instead of battery)
        uptime_sensor = @ha_service.entity("sensor.heltec_htit_tracker_device_uptime")
        uptime = uptime_sensor ? uptime_sensor["state"].to_i : nil

        {
          lat: lat_sensor["state"].to_f,
          lng: lng_sensor["state"].to_f,
          timestamp: Time.now,
          accuracy: gps_quality,  # 3=great, 2=degraded, 1/0=unavailable
          satellites: satellites,
          uptime: uptime,  # seconds of device uptime
          source: "gps"
        }
      rescue StandardError
        nil
      end

      def random_landmark_location
        landmark = Landmark.active.sample

        {
          lat: landmark.latitude.to_f,
          lng: landmark.longitude.to_f,
          timestamp: Time.now,
          accuracy: nil,
          satellites: nil,
          uptime: nil,
          source: "random_landmark"
        }
      end
    end
  end
end
