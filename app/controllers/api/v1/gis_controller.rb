# frozen_string_literal: true

class Api::V1::GisController < Api::V1::BaseController
      def streets
        begin
          # For now, return empty GeoJSON - will need to implement GisCacheService
          render json: { type: 'FeatureCollection', features: [], error: 'Streets data not yet implemented' }
        rescue StandardError => e
          render json: { type: 'FeatureCollection', features: [], error: 'Streets data unavailable' }
        end
      end

      def blocks
        begin
          # For now, return empty GeoJSON - will need to implement GisCacheService
          render json: { type: 'FeatureCollection', features: [], error: 'Blocks data not yet implemented' }
        rescue StandardError => e
          render json: { type: 'FeatureCollection', features: [], error: 'Blocks data unavailable' }
        end
      end

      def landmarks_nearby
        lat = params[:lat]&.to_f
        lng = params[:lng]&.to_f

        if lat && lng
          # Use location context service for consistency
          context = Services::Gps::LocationContextService.full_context(lat, lng)
          render json: {
            landmarks: context[:landmarks] || [],
            count: (context[:landmarks] || []).length,
            center: { lat: lat, lng: lng },
            source: 'location_context'
          }
        else
          render json: { error: 'Missing lat/lng parameters' }, status: :bad_request
        end
      end

      def initial
        # Load trash fence and all landmarks except toilets
        fence = Boundary.trash_fence
        all_landmarks = Landmark.active.where.not(landmark_type: 'toilet')
        features = []
        
        # Add trash fence
        if fence
          features << {
            type: 'Feature',
            geometry: {
              type: 'Polygon',
              coordinates: fence.coordinates
            },
            properties: {
              id: "boundary-#{fence.id}",
              name: fence.name,
              feature_type: 'boundary'
            }
          }
        end
        
        # Add all landmarks (except toilets)
        all_landmarks.each do |landmark|
          feature_type = case landmark.landmark_type
                         when 'center', 'sacred', 'gathering' then 'major_landmark'
                         else 'landmark'
                         end
          features << {
            type: 'Feature',
            geometry: {
              type: 'Point',
              coordinates: [landmark.longitude.to_f, landmark.latitude.to_f]
            },
            properties: {
              id: "landmark-#{landmark.id}",
              name: landmark.name,
              feature_type: feature_type,
              landmark_type: landmark.landmark_type
            }
          }
        end
        
        render json: {
          type: 'FeatureCollection',
          features: features,
          count: features.length,
          source: 'initial_load'
        }
      rescue StandardError => e
        render json: {
          type: 'FeatureCollection',
          features: [],
          count: 0,
          error: e.message
        }
      end

      def trash_fence
        begin
          # For now, return empty GeoJSON - will need to implement GisCacheService
          render json: { type: 'FeatureCollection', features: [], error: 'Trash fence data not yet implemented' }
        rescue StandardError => e
          render json: { type: 'FeatureCollection', features: [], error: 'Trash fence data unavailable' }
        end
      end
end