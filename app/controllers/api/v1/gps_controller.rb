# frozen_string_literal: true

class Api::V1::GpsController < Api::V1::BaseController
  # Reduce logging noise for high-frequency GPS endpoints
  def self.silencer
    @silencer ||= ActiveSupport::LogSubscriber.new
  end

  around_action :silence_gps_logging, only: [:location, :coords, :proximity]
  def location
    begin
      # Get current location with full context
      location_data = ::Gps::GPSTrackingService.new.current_location

      if location_data.nil?
        render json: {
          error: "GPS tracking not available",
          message: "No GPS data - no Home Assistant connection",
          timestamp: Time.now.utc.iso8601
        }, status: :service_unavailable
      else
        render json: location_data
      end
    rescue StandardError => e
      render json: {
        error: "GPS service error",
        message: e.message,
        timestamp: Time.now.utc.iso8601
      }, status: :internal_server_error
    end
  end

  def coords
    location = ::Gps::GPSTrackingService.new.current_location
    if location&.dig(:lat) && location[:lng]
      render json: {
        lat: location[:lat],
        lng: location[:lng]
      }
    else
      render json: { error: "No GPS coordinates available" }, status: :service_unavailable
    end
  rescue StandardError => e
    render json: { error: "GPS coords error", details: e.message }, status: :internal_server_error
  end

  def proximity
    begin
      current_loc = ::Gps::GPSTrackingService.new.current_location
      if current_loc && current_loc[:lat] && current_loc[:lng]
        proximity = ::Gps::GPSTrackingService.new.proximity_data(current_loc[:lat], current_loc[:lng])
        render json: proximity
      else
        render json: { landmarks: [], portos: [], map_mode: "normal", visual_effects: [] }
      end
    rescue StandardError => e
      render json: {
        landmarks: [],
        portos: [],
        map_mode: "normal",
        visual_effects: [],
        error: e.message
      }
    end
  end

  def home
    home_coords = GlitchCube.home_camp_coordinates
    render json: home_coords
  end

  def simulate_movement
    begin
      if GlitchCube.gps_spoofing_allowed?
        result = ::Gps::GPSTrackingService.new.simulate_movement!
        render json: result
      else
        render json: { error: "Simulation mode not enabled" }, status: :bad_request
      end
    rescue StandardError => e
      render json: { error: "Simulation failed", details: e.message }, status: :internal_server_error
    end
  end

  def movement_status
    begin
      if GlitchCube.gps_spoofing_allowed?
        result = ::Gps::GPSTrackingService.new.movement_status
        render json: result
      else
        render json: { error: "Simulation mode not enabled" }, status: :bad_request
      end
    rescue StandardError => e
      render json: { error: "Status check failed", details: e.message }, status: :internal_server_error
    end
  end

  def set_destination
    begin
      if GlitchCube.gps_spoofing_allowed?
        landmark_name = params[:landmark]
        unless landmark_name
          render json: { error: "landmark parameter required" }, status: :bad_request
          return
        end

        result = ::Gps::GPSTrackingService.new.set_destination(landmark_name)
        render json: result
      else
        render json: { error: "Simulation mode not enabled" }, status: :bad_request
      end
    rescue StandardError => e
      render json: { error: "Destination setting failed", details: e.message }, status: :internal_server_error
    end
  end

  def stop_movement
    begin
      if GlitchCube.gps_spoofing_allowed?
        result = ::Gps::GPSTrackingService.new.stop_movement
        render json: result
      else
        render json: { error: "Simulation mode not enabled" }, status: :bad_request
      end
    rescue StandardError => e
      render json: { error: "Stop movement failed", details: e.message }, status: :internal_server_error
    end
  end

  def history
    begin
      # Simple history endpoint - will generate over time
      # For now return current location as single point
      current_loc = ::Gps::GPSTrackingService.new.current_location

      if current_loc && current_loc[:lat] && current_loc[:lng]
        history = [ {
          lat: current_loc[:lat],
          lng: current_loc[:lng],
          timestamp: Time.now.iso8601,
          address: current_loc[:address] || "Unknown location"
        } ]
        render json: { history: history, total_points: 1, mode: "live" }
      else
        render json: { history: [], total_points: 0, mode: "unavailable", message: "GPS not available" }
      end
    rescue StandardError => e
      render json: { error: "Unable to fetch GPS history", history: [], total_points: 0 }
    end
  end

  def cube_current_loc
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"

    begin
      # Get GPS coordinates
      location = ::Gps::GPSTrackingService.new.current_location
      if location.nil? || !location[:lat] || !location[:lng]
        render plain: "GPS unavailable", status: :service_unavailable
        return
      end

      # Get zone and address info
      context = ::Gps::LocationContextService.full_context(location[:lat], location[:lng])

      # Return simple text: address if in city, zone otherwise
      if context[:zone] == :city && context[:address]
        render plain: context[:address]
      else
        render plain: context[:zone].to_s.humanize
      end
    rescue StandardError => e
      render json: {
        error: "GPS service error",
        message: e.message,
        timestamp: Time.now.utc.iso8601
      }, status: :internal_server_error
    end
  end

  def landmarks
    # Cache landmarks forever - they don't move
    response.headers["Cache-Control"] = "public, max-age=31536000" # 1 year
    response.headers["Expires"] = (Time.now + 31_536_000).httpdate

    begin
      # Load all landmarks from database (cacheable since they don't move)
      landmarks = Landmark.active.order(:name).map do |landmark|
        {
          name: landmark.name,
          lat: landmark.latitude.to_f,
          lng: landmark.longitude.to_f,
          type: landmark.landmark_type,
          priority: case landmark.landmark_type
                    when "center", "sacred" then 1 # Highest priority for Man, Temple
                    when "medical", "ranger" then 2  # High priority for emergency services
                    when "service", "toilet" then 3  # Medium priority for utilities
                    when "art" then 4 # Lower priority for art
                    else 5 # Lowest priority for other landmarks
                    end,
          description: landmark.description || landmark.name
        }
      end

      render json: {
        landmarks: landmarks,
        count: landmarks.length,
        source: "Database (Burning Man Innovate GIS Data 2025)",
        cache_hint: "forever" # Landmarks don't move, safe to cache indefinitely
      }
    rescue StandardError => e
      # Fallback to hardcoded landmarks if database unavailable
      render json: {
        landmarks: [],
        count: 0,
        source: "Fallback (empty)",
        error: "Database unavailable: #{e.message}"
      }
    end
  end

  private

  def silence_gps_logging
    Rails.logger.silence(Logger::WARN) do
      yield
    end
  end
end
