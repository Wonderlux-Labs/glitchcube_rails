# frozen_string_literal: true

# Simple service to get GPS coordinates from Home Assistant
# All location context comes from LocationContextService
module Services
  module Gps
    class GPSTrackingService
      def initialize
        @ha_client = ::Services::Core::HomeAssistantClient.new
      end

      # Get current GPS coordinates with full location context
      def current_location
        # Check for spoofed GPS first (development only), then Home Assistant, then fallback
        coords = fetch_spoofed_location || fetch_from_home_assistant || random_landmark_location

        # Get full context from LocationContextService (this is cached)
        context = Gps::LocationContextService.full_context(coords[:lat], coords[:lng])

        # Merge GPS metadata with location context
        coords.merge(context)
      end

      # Get proximity data for map reactions using LocationContextService
      def proximity_data(lat, lng)
        context = Gps::LocationContextService.full_context(lat, lng)
        landmarks = context[:landmarks] || []

        {
          landmarks: landmarks,
          portos: context[:nearest_porto] ? [context[:nearest_porto]] : [],
          map_mode: determine_map_mode_from_landmarks(landmarks),
          visual_effects: determine_visual_effects_from_landmarks(landmarks)
        }
      end

      # Deprecated method for backward compatibility
      def brc_address_from_coordinates(lat, lng)
        context = Gps::LocationContextService.full_context(lat, lng)
        context[:address]
      end

      # Simulate cube movement - pick a destination and walk toward it
      def simulate_movement!
        return unless GlitchCube.config.gps_spoofing_allowed?

        begin
          redis = Redis.new(url: GlitchCube.config.redis_url)
          current_data = redis.get('current_cube_location')
          destination_data = redis.get('cube_destination')

          # If no current location, start at a random landmark
          unless current_data
            landmark = Landmark.active.order('RANDOM()').first
            current_location = {
              lat: landmark.latitude.to_f,
              lng: landmark.longitude.to_f,
              timestamp: Time.now.iso8601
            }
            redis.setex('current_cube_location', 3600, current_location.to_json)
            return
          end

          current = JSON.parse(current_data, symbolize_names: true)

          # If no destination or reached destination, pick a new one
          if !destination_data || reached_destination?(current, destination_data)
            new_destination = pick_random_destination
            redis.setex('cube_destination', 7200, new_destination.to_json) # 2 hour destination
            destination = new_destination
          else
            destination = JSON.parse(destination_data, symbolize_names: true)
          end

          # Move toward destination (small step)
          new_location = move_toward_destination(current, destination)
          redis.setex('current_cube_location', 3600, new_location.to_json)
        rescue StandardError => e
          # Fallback - just stay put
          nil
        end
      end

      private

      def fetch_spoofed_location
        # Allow spoofed locations in development OR if explicitly enabled
        return nil unless GlitchCube.config.gps_spoofing_allowed?

        begin
          redis = Redis.new(url: GlitchCube.config.redis_url)
          spoofed_data = redis.get('current_cube_location')
          return nil unless spoofed_data

          data = JSON.parse(spoofed_data, symbolize_names: true)
          {
            lat: data[:lat],
            lng: data[:lng],
            timestamp: Time.parse(data[:timestamp]),
            accuracy: nil,
            satellites: nil,
            uptime: nil,
            source: 'spoofed'
          }
        rescue StandardError
          nil
        end
      end

      def pick_random_destination
        # Pick a random landmark as destination
        landmark = Landmark.active.order('RANDOM()').first
        {
          lat: landmark.latitude.to_f,
          lng: landmark.longitude.to_f,
          name: landmark.name,
          timestamp: Time.now.iso8601
        }
      end

      def reached_destination?(current, destination_data)
        destination = JSON.parse(destination_data, symbolize_names: true)
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
        rlat1, rlng1, rlat2, rlng2 = [lat1, lng1, lat2, lng2].map { |d| d * rad_per_deg }

        dlat = rlat2 - rlat1
        dlng = rlng2 - rlng1

        a = (Math.sin(dlat / 2)**2) + (Math.cos(rlat1) * Math.cos(rlat2) * (Math.sin(dlng / 2)**2))
        c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

        6_371_000 * c # Earth radius in meters
      end

      def determine_map_mode_from_landmarks(landmarks)
        return 'normal' if landmarks.empty?

        primary = landmarks.first
        case primary[:type]
        when 'sacred' then 'temple'
        when 'center' then 'man'
        when 'medical' then 'emergency'
        when 'service' then 'service'
        else 'landmark'
        end
      end

      def determine_visual_effects_from_landmarks(landmarks)
        effects = []

        landmarks.each do |landmark|
          case landmark[:type]
          when 'sacred'
            effects << { type: 'aura', color: 'white', intensity: 'soft' }
          when 'center'
            effects << { type: 'pulse', color: 'orange', intensity: 'strong' }
          when 'medical'
            effects << { type: 'beacon', color: 'red', intensity: 'steady' }
          when 'service'
            effects << { type: 'glow', color: 'blue', intensity: 'medium' }
          end
        end

        effects
      end

      def fetch_from_home_assistant
        # Get latitude and longitude from the glitchcube sensors
        lat_sensor = @ha_client.states.find { |s| s['entity_id'] == 'sensor.glitchcube_latitude' }
        lng_sensor = @ha_client.states.find { |s| s['entity_id'] == 'sensor.glitchcube_longitude' }

        return nil unless lat_sensor && lng_sensor

        # Get GPS quality from HTIT tracker
        quality_sensor = @ha_client.states.find { |s| s['entity_id'] == 'sensor.heltec_htit_tracker_gps_quality' }
        gps_quality = quality_sensor ? quality_sensor['state'].to_i : nil

        # Get satellite count from HTIT tracker
        sat_sensor = @ha_client.states.find { |s| s['entity_id'] == 'sensor.heltec_htit_tracker_satellites' }
        satellites = sat_sensor ? sat_sensor['state'].to_i : nil

        # Get device uptime from HTIT tracker (instead of battery)
        uptime_sensor = @ha_client.states.find { |s| s['entity_id'] == 'sensor.heltec_htit_tracker_device_uptime' }
        uptime = uptime_sensor ? uptime_sensor['state'].to_i : nil

        {
          lat: lat_sensor['state'].to_f,
          lng: lng_sensor['state'].to_f,
          timestamp: Time.now,
          accuracy: gps_quality,  # 3=great, 2=degraded, 1/0=unavailable
          satellites: satellites,
          uptime: uptime,  # seconds of device uptime
          source: 'gps'
        }
      rescue StandardError
        nil
      end

      def random_landmark_location
        landmark = Landmark.active.order('RANDOM()').first

        {
          lat: landmark.latitude.to_f,
          lng: landmark.longitude.to_f,
          timestamp: Time.now,
          accuracy: nil,
          satellites: nil,
          uptime: nil,
          source: 'random_landmark'
        }
      end
    end
  end
end
