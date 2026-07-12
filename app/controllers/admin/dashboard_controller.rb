# app/controllers/admin/dashboard_controller.rb

class Admin::DashboardController < Admin::BaseController
  def index
    @stats = {
      conversations: conversation_stats,
      summaries: summary_stats,
      world_state: world_state_stats,
      jobs: job_stats,
      system: system_stats
    }

    @recent_activity = recent_activity_feed
  end

  private

  def conversation_stats
    {
      total: Conversation.count,
      active: Conversation.active.count,
      finished_today: Conversation.finished.where(ended_at: 1.day.ago..Time.current).count,
      avg_duration: average_finished_duration
    }
  end

  # `duration` is computed in Ruby from started_at/ended_at (see Conversation#duration),
  # not a DB column, so this can't be a plain .average(:duration).
  def average_finished_duration
    durations = Conversation.finished.pluck(:started_at, :ended_at).filter_map { |s, e| e - s if s && e }
    return 0 if durations.empty?

    (durations.sum / durations.size).round(2)
  end

  def summary_stats
    {
      today: Summary.where(created_at: Date.current.beginning_of_day..Date.current.end_of_day).count,
      week: Summary.where(created_at: 1.week.ago..Time.current).count,
      latest_overall_at: Summary.overall.recent.first&.created_at,
      latest_interaction_at: Summary.interaction.recent.first&.created_at,
      by_type: Summary.group(:summary_type).count
    }
  end

  def world_state_stats
    begin
      world_state = HomeAssistantService.entity("sensor.glitchcube_world_state")
      {
        status: world_state ? "active" : "inactive",
        last_updated: world_state&.dig("attributes", "last_changed"),
        total_sensors: HomeAssistantService.entities_by_domain("sensor").count
      }
    rescue StandardError => e
      {
        status: "error",
        error: e.message,
        total_sensors: 0
      }
    end
  end

  def job_stats
    # Mirrors config/recurring.yml — Mission Control (/jobs) has full detail.
    {
      interaction_summary: "Every 10 min",
      overall_summary: "Hourly",
      random_persona: "Checks every 5 min",
      conversation_timeout_monitor: "Every minute"
    }
  end

  def system_stats
    {
      rails_env: Rails.env,
      uptime: Time.current - Rails.application.config.booted_at,
      home_assistant: HomeAssistantService.available?,
      llm_service: LlmService.available?
    }
  end

  def recent_activity_feed
    activities = []

    # Recent conversations
    Conversation.recent.limit(5).each do |conv|
      activities << {
        type: "conversation",
        title: "Conversation #{conv.session_id[0..8]}...",
        subtitle: "#{conv.persona} - #{conv.active? ? 'Active' : 'Finished'}",
        timestamp: conv.updated_at,
        path: admin_conversation_path(conv)
      }
    end

    # Recent summaries
    Summary.recent.limit(3).each do |summary|
      activities << {
        type: "summary",
        title: "#{summary.summary_type.humanize} summary#{" (#{summary.persona.name || summary.persona.slug})" if summary.persona}",
        subtitle: summary.summary_text.truncate(60),
        timestamp: summary.created_at,
        path: admin_summary_path(summary)
      }
    end

    activities.sort_by { |a| a[:timestamp] }.reverse.first(10)
  end
end
