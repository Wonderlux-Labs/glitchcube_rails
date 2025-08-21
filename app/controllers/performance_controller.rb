# app/controllers/performance_controller.rb
# Web interface for performance mode management

class PerformanceController < ApplicationController
  def index
    @session_id = params[:session_id] || "web_performance_session"
    @active_performance = CubePerformance.performance_status(@session_id)
  end

  def start
    session_id = params[:session_id] || "web_performance_session"
    performance_type = params[:performance_type]
    duration_minutes = params[:duration_minutes].to_i

    begin
      case performance_type
      when "standup_comedy"
        CubePerformance.standup_comedy(
          duration_minutes: duration_minutes,
          session_id: session_id
        )
      when "adventure_story"
        CubePerformance.adventure_story(
          duration_minutes: duration_minutes,
          session_id: session_id
        )
      when "improv"
        CubePerformance.improv_session(
          duration_minutes: duration_minutes,
          session_id: session_id
        )
      when "poetry"
        CubePerformance.poetry_slam(
          duration_minutes: duration_minutes,
          session_id: session_id
        )
      else
        flash[:error] = "Unknown performance type: #{performance_type}"
        redirect_to performance_index_path(session_id: session_id) and return
      end

      flash[:success] = "Started #{performance_type} performance for #{duration_minutes} minutes"

    rescue => e
      flash[:error] = "Failed to start performance: #{e.message}"
    end

    redirect_to performance_index_path(session_id: session_id)
  end

  def stop
    session_id = params[:session_id] || "web_performance_session"

    begin
      success = CubePerformance.stop_performance(session_id, reason: "web_interface_stop")

      if success
        flash[:success] = "Performance stopped"
      else
        flash[:warning] = "No active performance to stop"
      end

    rescue => e
      flash[:error] = "Failed to stop performance: #{e.message}"
    end

    redirect_to performance_index_path(session_id: session_id)
  end

  def status
    session_id = params[:session_id] || "web_performance_session"
    status = CubePerformance.performance_status(session_id)

    render json: status
  end
end
