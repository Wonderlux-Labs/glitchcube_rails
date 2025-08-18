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
          fetch_from_home_assistant || random_landmark_location
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
      def simulate_movement!(landmark_name = nil)
        return unless GlitchCube.gps_spoofing_allowed?

        begin
          # Get current cached location
          current_data = Rails.cache.read("gps_current_location")
          destination_data = Rails.cache.read("cube_destination")

          # If no current location, start at a random landmark
          unless current_data
            start_landmark = Landmark.active.order("RANDOM()").first
            set_location(start_landmark.latitude.to_f, start_landmark.longitude.to_f)
            return "Started at #{start_landmark.name}"
          end

          current = current_data

          # Set new destination if provided or if no destination exists
          if landmark_name
            landmark = Landmark.active.find_by(name: landmark_name)
            return "Landmark '#{landmark_name}' not found" unless landmark

            destination = {
              lat: landmark.latitude.to_f,
              lng: landmark.longitude.to_f,
              name: landmark.name
            }
            Rails.cache.write("cube_destination", destination.to_json, expires_in: 2.hours)
          elsif !destination_data
            # Pick random destination if none provided and none exists
            destination = pick_random_destination
            Rails.cache.write("cube_destination", destination.to_json, expires_in: 2.hours)
          else
            destination = JSON.parse(destination_data, symbolize_names: true)
          end

          # Check if we've reached the destination
          if reached_destination?(current, destination)
            Rails.cache.delete("cube_destination") # Clear destination
            return "Arrived at #{destination[:name]}"
          end

          # Move toward destination (small step)
          new_location = move_toward_destination(current, destination)
          set_location(new_location[:lat], new_location[:lng])

          distance = calculate_distance(current[:lat], current[:lng], destination[:lat], destination[:lng])
          "Moving toward #{destination[:name]} (#{distance.round}m remaining)"
        rescue StandardError => e
          "Movement simulation failed: #{e.message}"
        end
      end

      private


      def pick_random_destination
        # Pick a random landmark as destination
        landmark = Landmark.active.order("RANDOM()").first
        {
          lat: landmark.latitude.to_f,
          lng: landmark.longitude.to_f,
          name: landmark.name,
          timestamp: Time.now.iso8601
        }
      end

      def reached_destination?(current, destination)
        distance = calculate_distance(current[:lat], current[:lng], destination[:lat], destination[:lng])
        distance < 50 # Within 50 meters
      end

      def move_toward_destination(current, destination)
        # Calculate direction and take a small step
        lat_diff = destination[:lat] - current[:lat]
        lng_diff = destination[:lng] - current[:lng]

        # Step size (about 10-20 meters)
        step_size = 0.0001

        # Normalize direction and apply step
        distance = Math.sqrt((lat_diff**2) + (lng_diff**2))
        return current if distance.zero?

        new_lat = current[:lat] + ((lat_diff / distance) * step_size)
        new_lng = current[:lng] + ((lng_diff / distance) * step_size)

        {
          lat: new_lat,
          lng: new_lng,
          timestamp: Time.now.iso8601
        }
      end

      def calculate_distance(lat1, lng1, lat2, lng2)
        # Haversine formula for distance in meters
        rad_per_deg = Math::PI / 180
        rlat1, rlng1, rlat2, rlng2 = [ lat1, lng1, lat2, lng2 ].map { |d| d * rad_per_deg }

        dlat = rlat2 - rlat1
        dlng = rlng2 - rlng1

        a = (Math.sin(dlat / 2)**2) + (Math.cos(rlat1) * Math.cos(rlat2) * (Math.sin(dlng / 2)**2))
        c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

        6_371_000 * c # Earth radius in meters
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
        landmark = Landmark.active.order("RANDOM()").first

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
