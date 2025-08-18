# app/controllers/api/base_controller.rb
class Api::BaseController < ApplicationController
  # Skip CSRF token verification for API endpoints
  skip_before_action :verify_authenticity_token
  
  # Base controller for all API endpoints
  # Add common API functionality here
  
  private
  
  def render_api_error(message, status = :unprocessable_entity)
    render json: { error: message }, status: status
  end
  
  def render_api_success(data, status = :ok)
    render json: { success: true, data: data }, status: status
  end
end