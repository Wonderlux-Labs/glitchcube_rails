# frozen_string_literal: true

module Routes
  module Api
    module Gps
      def self.registered(app)
        # GPS Tracking Routes
        app.get '/gps' do
          erb :gps_map, views: File.expand_path('../../../views', __dir__)
        end
        # Simple coords endpoint - just lat/lng
        app.get '/api/v1/gps/coords' do
          location = Services::Gps::GPSTrackingService.new.current_location
          if location&.dig(:lat) && location[:lng]
            json({
                   lat: location[:lat],
                   lng: location[:lng]
                 })
          else
            status 503
            json({ error: 'No GPS coordinates available' })
          end
        rescue StandardError => e
          Services::Logging::SimpleLogger.log_api_call(
            service: 'GPS API',
            endpoint: '/api/v1/gps/coords',
            error: e.message,
            success: false
          )
          status 500
          json({ error: 'GPS coords error', details: e.message })
        end
        app.get '/api/v1/gps/location' do
          content_type :json
          begin
            # Get current location with full context
            location = Services::Gps::GPSTrackingService.new.current_location
            if location.nil?
              status 503 # Service Unavailable
              json({
                     error: 'GPS tracking not available',
                     message: 'No GPS data - no Home Assistant connection',
                     timestamp: Time.now.utc.iso8601
                   })
            else
              json(location)
            end
          rescue StandardError => e
            status 500
            json({
                   error: 'GPS service error',
                   message: e.message,
                   timestamp: Time.now.utc.iso8601
                 })
          end
        end
        app.get '/api/v1/gps/proximity' do
          content_type :json
          begin
            # Get current location
            current_loc = Services::Gps::GPSTrackingService.new.current_location
            if current_loc && current_loc[:lat] && current_loc[:lng]
              proximity = Services::Gps::GPSTrackingService.new.proximity_data(current_loc[:lat], current_loc[:lng])
              json(proximity)
            else
              json({ landmarks: [], portos: [], map_mode: 'normal', visual_effects: [] })
            end
          rescue StandardError => e
            json({
                   landmarks: [],
                   portos: [],
                   map_mode: 'normal',
                   visual_effects: [],
                   error: e.message
                 })
          end
        end
        app.get '/api/v1/gps/home' do
          content_type :json
          home_coords = GlitchCube.config.home_camp_coordinates
          json(home_coords)
        end

        # Trigger cube movement simulation
        app.post '/api/v1/gps/simulate_movement' do
          content_type :json
          begin
            if GlitchCube.config.simulate_cube_movement?
              Services::Gps::GPSTrackingService.new.simulate_movement!
              json({ success: true, message: 'Movement simulation updated' })
            else
              status 400
              json({ error: 'Simulation mode not enabled' })
            end
          rescue StandardError => e
            status 500
            json({ error: 'Simulation failed', details: e.message })
          end
        end

        app.get '/api/v1/gps/history' do
          content_type :json
          begin
            # Simple history endpoint - will generate over time
            # For now return current location as single point
            current_loc = Services::Gps::GPSTrackingService.new.current_location

            if current_loc && current_loc[:lat] && current_loc[:lng]
              history = [{
                lat: current_loc[:lat],
                lng: current_loc[:lng],
                timestamp: Time.now.iso8601,
                address: current_loc[:address] || 'Unknown location'
              }]
              json({ history: history, total_points: 1, mode: 'live' })
            else
              json({ history: [], total_points: 0, mode: 'unavailable', message: 'GPS not available' })
            end
          rescue StandardError => e
            Services::Logging::SimpleLogger.log_api_call(
              service: 'GPS History',
              endpoint: '/api/v1/gps/history',
              error: e.message,
              success: false
            )
            json({ error: 'Unable to fetch GPS history', history: [], total_points: 0 })
          end
        end
        # Essential GeoJSON data endpoints for map overlay
        app.get '/api/v1/gis/streets' do
          content_type :json
          begin
            result = Services::GisCacheService.cached_streets
            json(result)
          rescue StandardError
            json({ type: 'FeatureCollection', features: [], error: 'Streets data unavailable' })
          end
        end

        app.get '/api/v1/gis/blocks' do
          content_type :json
          begin
            result = Services::GisCacheService.cached_city_blocks
            json(result)
          rescue StandardError
            json({ type: 'FeatureCollection', features: [], error: 'Blocks data unavailable' })
          end
        end
        # Simplified nearby landmarks endpoint
        app.get '/api/v1/gis/landmarks/nearby' do
          content_type :json
          lat = params[:lat]&.to_f
          lng = params[:lng]&.to_f

          if lat && lng
            # Use location context service for consistency
            context = Services::Gps::LocationContextService.full_context(lat, lng)
            json({
                   landmarks: context[:landmarks] || [],
                   count: (context[:landmarks] || []).length,
                   center: { lat: lat, lng: lng },
                   source: 'location_context'
                 })
          else
            status 400
            json({ error: 'Missing lat/lng parameters' })
          end
        end
        # Load everything except toilets - full map view
        app.get '/api/v1/gis/initial' do
          content_type :json
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
          json({
                 type: 'FeatureCollection',
                 features: features,
                 count: features.length,
                 source: 'initial_load'
               })
        end
        app.get '/api/v1/gis/trash_fence' do
          content_type :json
          # Use cached data for this expensive operation
          result = Services::GisCacheService.cached_trash_fence
          json(result)
        end
        # External map app endpoint - FAST Redis-only response
        app.get '/api/v1/gps/cube_current_loc' do
          content_type :text
          # Add CORS headers for external app access
          headers 'Access-Control-Allow-Origin' => '*'
          headers 'Access-Control-Allow-Methods' => 'GET'
          headers 'Access-Control-Allow-Headers' => 'Content-Type'
          begin
            # Get GPS coordinates
            location = Services::Gps::GPSTrackingService.new.current_location
            if location.nil? || !location[:lat] || !location[:lng]
              status 503
              return 'GPS unavailable'
            end
            # Get zone and address info
            context = Services::Gps::LocationContextService.full_context(location[:lat], location[:lng])

            # Return simple text: address if in city, zone otherwise
            if context[:zone] == :city && context[:address]
              context[:address]
            else
              context[:zone].to_s.humanize
            end
          rescue StandardError => e
            Services::Logging::SimpleLogger.log_api_call(
              service: 'GPS External API',
              endpoint: '/api/v1/gps/cube_current_loc',
              error: e.message,
              success: false
            )
            status 500
            json({
                   error: 'GPS service error',
                   message: e.message,
                   timestamp: Time.now.utc.iso8601
                 })
          end
        end
        app.get '/api/v1/gps/landmarks' do
          content_type :json
          # Cache landmarks forever - they don't move
          headers 'Cache-Control' => 'public, max-age=31536000' # 1 year
          headers 'Expires' => (Time.now + 31_536_000).httpdate
          begin
            # Load all landmarks from database (cacheable since they don't move)
            landmarks = Landmark.active.order(:name).map do |landmark|
              {
                name: landmark.name,
                lat: landmark.latitude.to_f,
                lng: landmark.longitude.to_f,
                type: landmark.landmark_type,
                priority: case landmark.landmark_type
                          when 'center', 'sacred' then 1 # Highest priority for Man, Temple
                          when 'medical', 'ranger' then 2  # High priority for emergency services
                          when 'service', 'toilet' then 3  # Medium priority for utilities
                          when 'art' then 4 # Lower priority for art
                          else 5 # Lowest priority for other landmarks
                          end,
                description: landmark.description || landmark.name
              }
            end
            json({
                   landmarks: landmarks,
                   count: landmarks.length,
                   source: 'Database (Burning Man Innovate GIS Data 2025)',
                   cache_hint: 'forever' # Landmarks don't move, safe to cache indefinitely
                 })
          rescue StandardError => e
            # Fallback to hardcoded landmarks if database unavailable
            landmarks = Utils::BurningManLandmarks.all_landmarks
            json({
                   landmarks: landmarks,
                   count: landmarks.length,
                   source: 'Fallback (hardcoded)',
                   error: "Database unavailable: #{e.message}"
                 })
          end
        end
      end
    end
  end
end
