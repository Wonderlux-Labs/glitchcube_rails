# app/controllers/admin/dashboard_controller.rb

class Admin::DashboardController < Admin::BaseController
  def index
    @stats = {
      conversations: conversation_stats,
      memories: memory_stats,
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
      avg_duration: Conversation.finished.average(:duration)&.round(2) || 0
    }
  end
  
  def memory_stats
    {
      total: ConversationMemory.count,
      by_type: ConversationMemory.group(:memory_type).count,
      high_importance: ConversationMemory.high_importance.count,
      recent: ConversationMemory.where(created_at: 1.day.ago..Time.current).count
    }
  end
  
  def world_state_stats
    begin
      world_state = HomeAssistantService.entity('sensor.world_state')
      {
        status: world_state ? 'active' : 'inactive',
        last_weather_update: world_state&.dig('attributes', 'weather_updated_at'),
        total_sensors: HomeAssistantService.entities_by_domain('sensor').count
      }
    rescue StandardError => e
      {
        status: 'error',
        error: e.message,
        total_sensors: 0
      }
    end
  end
  
  def job_stats
    # Basic stats - Mission Control provides detailed job info
    {
      weather_jobs: 'Hourly',
      timeout_monitor: 'Every minute',  
      memory_extraction: 'Every 30 minutes'
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
        type: 'conversation',
        title: "Conversation #{conv.session_id[0..8]}...",
        subtitle: "#{conv.persona} - #{conv.active? ? 'Active' : 'Finished'}",
        timestamp: conv.updated_at,
        path: admin_conversation_path(conv)
      }
    end
    
    # Recent memories
    ConversationMemory.recent.limit(3).each do |memory|
      activities << {
        type: 'memory',
        title: "#{memory.memory_type.humanize} memory",
        subtitle: memory.summary.truncate(60),
        timestamp: memory.created_at,
        path: admin_memory_path(memory)
      }
    end
    
    activities.sort_by { |a| a[:timestamp] }.reverse.first(10)
  end
end