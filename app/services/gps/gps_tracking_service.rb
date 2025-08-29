# frozen_string_literal: true

# Simple service to get GPS coordinates from Home Assistant
# All location context comes from LocationContextService
module Gps
  class GPSTrackingService
      def self.current_location
        new.current_location
      end

      def initialize
        @ha_service = HomeAssistantService.new
        @current_location = current_location
      end

      # Get current GPS coordinates with full location context
      def current_location
        @current_location = Rails.cache.fetch(:gps_current_location, expires_in: 5.minutes) do
          # Try to get real GPS data from Home Assistant first
          gps_data = fetch_from_home_assistant
          return random_landmark_location if gps_data.nil? || gps_data.blank?
          return random_landmark_location if gps_data[:lng].to_i.zero?
          # Fall back to random landmark if GPS unavailable
          gps_data || random_landmark_location
        end

        context = Gps::LocationContextService.full_context(@current_location[:lat], @current_location[:lng])
        @current_location.merge(context)
      end

      def set_random_location
        land = Landmark.where.not(landmark_type: "toilet").sample
        set_location(coords: "#{land.latitude}, #{land.longitude}")
      end

      # Get proximity data for map reactions using LocationContextService
      def proximity_data(lat, lng)
        context = Gps::LocationContextService.full_context(lat, lng)
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
        context = Gps::LocationContextService.full_context(lat, lng)
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
        @current_location = current_location
        true
      end

      # Simulate cube movement - walk toward a landmark and stop when reached
      def simulate_movement!(landmark: nil)
        current_data = current_location # Get fresh location instead of cached @current_location
        begin
          destination_data = Rails.cache.read("cube_destination")
          destination = if destination_data
                          JSON.parse(destination_data, symbolize_names: true)
          elsif landmark
                          {
                            lat: landmark.latitude.to_f,
                            lng: landmark.longitude.to_f,
                            name: landmark.name
                          }
          else
                          # Pick a random destination if none specified
                          pick_random_destination
          end

          Rails.cache.write("cube_destination", destination.to_json, expires_in: 2.hours)
          destination_landmark = Landmark.find_by(name: destination[:name])

          # Check if we've reached the destination
          if reached_destination?(current_data, destination_landmark)
            Rails.cache.delete("cube_destination") # Clear destination
            return {
              status: "arrived",
              message: "Arrived at #{destination[:name]}",
              location: current_data,
              destination: destination
            }
          end

          # Move toward destination (small step)
          new_location = move_toward_destination(current_data, destination)

          # Update location immediately without cache interference
          location_data = {
            lat: new_location[:lat],
            lng: new_location[:lng],
            timestamp: Time.now,
            source: "simulation",
            accuracy: 5.0, # Simulated accuracy
            satellites: 12,
            uptime: nil
          }

          # Write directly to cache and bypass the 5-minute cache
          Rails.cache.write("gps_current_location", location_data, expires_in: 5.minutes)
          @current_location = location_data

          distance = calculate_distance(current_data[:lat], current_data[:lng], destination[:lat], destination[:lng])

          # Start continuous movement if this is the first step
          if destination_data.nil?
            Recurring::System::MovementSimulationJob.perform_later
          end

          {
            status: "moving",
            message: "Moving toward #{destination[:name]} (#{distance.round}m remaining)",
            location: new_location,
            destination: destination,
            distance_remaining: distance.round
          }
        rescue StandardError => e
          Rails.logger.error "Movement simulation failed: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          {
            status: "error",
            message: "Movement simulation failed: #{e.message}",
            error: e.message
          }
        end
      end

      # Get current movement status without moving
      def movement_status
        destination_data = Rails.cache.read("cube_destination")
        return { status: "idle", message: "No active movement" } unless destination_data

        begin
          destination = JSON.parse(destination_data, symbolize_names: true)
          current_data = current_location
          destination_landmark = Landmark.find_by(name: destination[:name])

          if reached_destination?(current_data, destination_landmark)
            Rails.cache.delete("cube_destination")
            return {
              status: "arrived",
              message: "Arrived at #{destination[:name]}",
              location: current_data
            }
          end

          distance = calculate_distance(current_data[:lat], current_data[:lng], destination[:lat], destination[:lng])

          {
            status: "moving",
            message: "Moving toward #{destination[:name]} (#{distance.round}m remaining)",
            location: current_data,
            destination: destination,
            distance_remaining: distance.round
          }
        rescue StandardError => e
          { status: "error", message: "Error checking movement status: #{e.message}" }
        end
      end

      # Set a specific destination for movement
      def set_destination(landmark_name)
        landmark = Landmark.find_by(name: landmark_name)
        return { error: "Landmark not found" } unless landmark

        destination = {
          lat: landmark.latitude.to_f,
          lng: landmark.longitude.to_f,
          name: landmark.name,
          timestamp: Time.now.iso8601
        }

        Rails.cache.write("cube_destination", destination.to_json, expires_in: 2.hours)

        # Start movement simulation
        Recurring::System::MovementSimulationJob.perform_later

        { success: true, destination: destination, message: "Movement started toward #{landmark_name}" }
      end

      # Stop current movement
      def stop_movement
        Rails.cache.delete("cube_destination")
        # Note: The background job will naturally stop when it sees no destination
        { success: true, message: "Movement stopped" }
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

        distance = destination.distance_from(current[:lat], current[:lng]) * 1609.34 # Convert miles to meters
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
