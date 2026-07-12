# app/controllers/home_assistant_controller.rb
class HomeAssistantController < ApplicationController
  before_action :authenticate_home_assistant


  # Health check endpoint for Home Assistant
  def health
    render json: {
      status: "ok",
      service: "GlitchCube Voice Assistant",
      timestamp: Time.current.iso8601
    }
  end

  # Get available entities endpoint (for context building)
  def entities
    entities = HomeAssistantService.entities.map do |entity|
      {
        entity_id: entity["entity_id"],
        name: entity.dig("attributes", "friendly_name") || entity["entity_id"],
        domain: entity["entity_id"].split(".").first,
        state: entity["state"]
      }
    end

    render json: { entities: entities }
  rescue StandardError => e
    Rails.logger.error "Error fetching entities: #{e.message}"
    render json: { error: "Unable to fetch entities" }, status: 500
  end

  # Trigger an allowlisted world state service by name.
  def trigger_world_state_service
    service_class = params[:service_class]

    return render json: { error: "service_class required" }, status: 400 if service_class.blank?

    klass = WorldStateUpdaters::Registry.fetch(service_class)
    return render json: { error: "invalid service" }, status: 404 unless klass

    begin
      klass.call
      render json: { status: "ok" }
    rescue StandardError => e
      Rails.logger.error "World state service error: #{e.message}"
      render json: { error: "service failed" }, status: 500
    end
  end

  private

  def authenticate_home_assistant
    # Simple token-based authentication
    token = request.headers["Authorization"]&.gsub("Bearer ", "")

    unless token == Rails.configuration.home_assistant_token
      render json: { error: "Unauthorized" }, status: 401
    end
  end
end
