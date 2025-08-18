# app/jobs/goal_monitor_job.rb

class GoalMonitorJob < ApplicationJob
  queue_as :default
  
  def perform
    return unless Rails.env.production? || Rails.env.development?
    
    Rails.logger.info "🎯 GoalMonitorJob starting"
    
    # Check if we need to switch to safety goals
    check_safety_conditions
    
    # Check if current goal has expired
    check_goal_expiration
    
    # Auto-complete goals if the persona has indicated completion
    check_for_goal_completion
    
    Rails.logger.info "✅ GoalMonitorJob completed successfully"
  rescue StandardError => e
    Rails.logger.error "❌ GoalMonitorJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
  
  private
  
  def check_safety_conditions
    safety_active = GoalService.safety_mode_active?
    current_goal = GoalService.current_goal_status
    
    return unless current_goal
    
    # If safety mode is active but we don't have a safety goal, switch
    if safety_active && !current_goal[:category].include?('safety')
      Rails.logger.info "⚠️ Safety mode active - switching to safety goal"
      GoalService.request_new_goal(reason: 'safety_mode_activated')
    # If safety mode is off but we have a safety goal, switch to regular goal
    elsif !safety_active && current_goal[:category].include?('safety')
      Rails.logger.info "✅ Safety mode deactivated - switching to regular goal"
      GoalService.request_new_goal(reason: 'safety_mode_deactivated')
    end
  end
  
  def check_goal_expiration
    return unless GoalService.goal_expired?
    
    Rails.logger.info "⏰ Goal expired - completing and selecting new goal"
    GoalService.complete_goal(completion_notes: "Goal expired after time limit")
    GoalService.select_goal # Select new goal with default time limit
  end
  
  def check_for_goal_completion
    # Look for recent conversation logs that indicate goal completion
    recent_logs = ConversationLog.where('created_at > ?', 10.minutes.ago)
                                .order(created_at: :desc)
                                .limit(10)
    
    return if recent_logs.empty?
    
    goal_completion_phrases = [
      /goal\s+(complete|completed|done|finished)/i,
      /i\s+(completed|finished|achieved)\s+my\s+goal/i,
      /mission\s+(accomplished|complete)/i,
      /task\s+(complete|completed|done)/i,
      /i.*did\s+it/i,
      /success.*goal/i
    ]
    
    recent_logs.each do |log|
      response = log.ai_response.to_s.downcase
      
      if goal_completion_phrases.any? { |phrase| response.match?(phrase) }
        Rails.logger.info "🎉 Detected goal completion in conversation - completing goal"
        GoalService.complete_goal(completion_notes: "Persona indicated goal completion")
        GoalService.select_goal # Select new goal
        break # Only process one completion per run
      end
    end
  end
end