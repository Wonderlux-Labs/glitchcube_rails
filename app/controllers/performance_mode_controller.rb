# app/controllers/performance_mode_controller.rb
# API endpoints for controlling performance mode

class PerformanceModeController < ApplicationController
  before_action :set_session_id

  # POST /performance_mode/start
  def start
    performance_type = params[:performance_type] || "comedy"
    duration_minutes = (params[:duration_minutes] || 10).to_i
    prompt = params[:prompt]
    persona = params[:persona]

    Rails.logger.info "🎭 Starting #{performance_type} performance for #{duration_minutes} minutes"

    begin
      # Check if there's already an active performance
      existing_performance = PerformanceModeService.get_active_performance(@session_id)
      if existing_performance&.is_running?
        render json: {
          error: "Performance already running for this session",
          current_performance: {
            type: existing_performance.performance_type,
            time_remaining: existing_performance.time_remaining
          }
        }, status: 422
        return
      end

      # Start new performance
      service = PerformanceModeService.start_performance(
        session_id: @session_id,
        performance_type: performance_type,
        duration_minutes: duration_minutes,
        prompt: prompt,
        persona: persona
      )

      render json: {
        message: "Performance mode started",
        session_id: @session_id,
        performance_type: performance_type,
        duration_minutes: duration_minutes,
        estimated_end_time: (Time.current + duration_minutes.minutes).iso8601
      }

    rescue => e
      Rails.logger.error "❌ Failed to start performance mode: #{e.message}"
      render json: {
        error: "Failed to start performance mode",
        details: e.message
      }, status: 500
    end
  end

  # POST /performance_mode/stop
  def stop
    reason = params[:reason] || "manual_stop"

    begin
      success = PerformanceModeService.stop_active_performance(@session_id, reason)

      if success
        render json: {
          message: "Performance mode stopped",
          reason: reason,
          session_id: @session_id
        }
      else
        render json: {
          message: "No active performance to stop",
          session_id: @session_id
        }, status: 404
      end

    rescue => e
      Rails.logger.error "❌ Failed to stop performance mode: #{e.message}"
      render json: {
        error: "Failed to stop performance mode",
        details: e.message
      }, status: 500
    end
  end

  # GET /performance_mode/status
  def status
    begin
      service = PerformanceModeService.get_active_performance(@session_id)

      if service && service.is_running?
        render json: {
          active: true,
          session_id: @session_id,
          performance_type: service.performance_type,
          time_remaining_seconds: service.time_remaining,
          time_remaining_minutes: (service.time_remaining / 60.0).round(1),
          duration_minutes: service.duration_minutes,
          start_time: service.instance_variable_get(:@start_time)&.iso8601,
          estimated_end_time: service.instance_variable_get(:@end_time)&.iso8601
        }
      else
        render json: {
          active: false,
          session_id: @session_id,
          message: "No active performance"
        }
      end

    rescue => e
      Rails.logger.error "❌ Failed to get performance status: #{e.message}"
      render json: {
        error: "Failed to get performance status",
        details: e.message
      }, status: 500
    end
  end

  # POST /performance_mode/interrupt
  # Called when wake word is detected during performance
  def interrupt
    begin
      service = PerformanceModeService.get_active_performance(@session_id)

      if service && service.is_running?
        service.interrupt_for_wake_word

        render json: {
          message: "Performance interrupted for wake word",
          session_id: @session_id
        }
      else
        render json: {
          message: "No active performance to interrupt",
          session_id: @session_id
        }, status: 404
      end

    rescue => e
      Rails.logger.error "❌ Failed to interrupt performance: #{e.message}"
      render json: {
        error: "Failed to interrupt performance",
        details: e.message
      }, status: 500
    end
  end

  private

  def set_session_id
    @session_id = params[:session_id] || request.headers["X-Session-ID"] || "default_performance_session"
  end
end
