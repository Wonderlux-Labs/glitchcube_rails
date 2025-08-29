# app/jobs/goal_monitor_job.rb

module Recurring
  module Persona
    class GoalMonitorJob < ApplicationJob
  queue_as :default

  def perform
    return unless Rails.env.production? || Rails.env.development?
    if GoalService.current_goal.nil?
      
    Rails.logger.info "🎯 GoalMonitorJob starting"

    check_goal_expiration
    check_for_goal_completion

    Rails.logger.info "✅ GoalMonitorJob completed successfully"
  rescue StandardError => e
    Rails.logger.error "❌ GoalMonitorJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  private


  def check_goal_expiration
    return unless GoalService.goal_expired?

    Rails.logger.info "⏰ Goal expired - completing and selecting new goal"
    GoalService.complete_goal(completion_notes: "Goal expired after time limit")
    GoalService.select_goal # Select new goal with default time limit
  end

  def check_for_goal_completion
    # Look for recent conversation logs that indicate goal completion
    recent_logs = ConversationLog.where("created_at > ?", 10.minutes.ago)
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
  end
end
