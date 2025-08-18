# frozen_string_literal: true

# DONT CHANGE THIS IMPLMENTATION JUST USE IT OR EXTEND IT MUCH BETTER NOW

module Services
  module Gps
    class LocationContextService
      attr_reader :lat, :lng, :lat_lng

      def self.full_context(lat, lng)
        new(lat, lng).full_context
      end

      def initialize(lat, lng)
        @lat = lat.to_f
        @lng = lng.to_f
        @lat_lng = { lat: @lat, lng: @lng }
      end

      # Get comprehensive location context
      # only thing that needs to go to ext service
      def full_context
        cache_key = "location_context:#{lat.round(6)},#{lng.round(6)}"

        # Try cache first using Rails.cache
        cached_result = Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
          compute_full_context
        end

        cached_result
      end

      # Zone determination methods
      def zone
        return :outside_event unless within_fence?
        return :city if in_city?
        return :inner_playa if near_the_man?

        :deep_playa
      end

      # Boundary checks
      def within_fence?
        Boundary.cube_within_fence?(lat, lng)
      end

      def in_city?
        Boundary.in_city?(lat, lng)
      end

      def near_the_man?(radius_meters = 757)
        the_man = Landmark.find_by(name: "The Man")
        return false unless the_man

        nearby = Landmark.nearest(lat: lat, lng: lng, limit: 1, max_distance_meters: radius_meters)
        nearby.any? && nearby.first.id == the_man.id
      end

      # Address and location info
      def address
        return nil unless zone == :city

        intersection_data = nearest_intersection
        "#{intersection_data[:radial]} & #{intersection_data[:arc]}"
      end

      def nearest_intersection
        Street.nearest_intersection(lat, lng)
      end

      def city_block
        block = Boundary.containing_city_block(lat, lng)
        return nil unless block

        {
          name: block.name,
          id: block.properties["fid"]
        }
      end

      # Landmark methods
      def nearby_landmarks(limit = 3)
        landmarks = Landmark.nearest(lat: lat, lng: lng, limit: limit)
        landmarks.map do |lm|
          {
            name: lm.name,
            type: lm.landmark_type,
            distance_meters: lm.distance_meters
          }
        end
      end

      def nearest_landmark_of_type(type)
        return nearby_landmarks if type == :all

        Landmark.where(landmark_type: type).nearest(lat: lat, lng: lng)
      end

      def nearest_porto
        nearest_landmark_of_type("toilet")&.first
      end

      # Distance calculations - now using clean PostGIS helpers
      def distance_from_man
        the_man = Landmark.the_man
        return "Unknown" unless the_man

        distance_meters = the_man.distance_from(lat, lng)
        format_distance(distance_meters)
      end

      def distance_to(other_lat, other_lng)
        distance_meters = Landmark.distance_between(lat, lng, other_lat, other_lng)
        format_distance(distance_meters)
      end

      def distance_to_landmark(landmark_name)
        landmark = Landmark.find_by(name: landmark_name)
        return "Unknown" unless landmark

        distance_meters = landmark.distance_from(lat, lng)
        format_distance(distance_meters)
      end

      # Convenience methods for quick checks
      def burning_man_location?
        within_fence?
      end

      private

      def compute_full_context
        {
          zone: zone,
          address: address,
          intersection: nearest_intersection,
          landmarks: nearby_landmarks(5),
          within_fence: within_fence?,
          city_block: city_block,
          distance_from_man: distance_from_man,
          nearest_porto: nearest_porto,
          lat_lng: lat_lng
        }
      end

      def format_distance(distance_meters)
        distance_miles = distance_meters / 1609.34

        if distance_miles < 0.1
          "#{(distance_miles * 5280).round} feet"
        else
          "#{distance_miles.round(2)} miles"
        end
      end
    end
  end
end
