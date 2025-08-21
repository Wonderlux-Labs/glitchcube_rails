# app/jobs/performance_mode_job.rb
# Background job to handle autonomous performance mode

class PerformanceModeJob < ApplicationJob
  queue_as :default

  def perform(session_id:, performance_type:, duration_minutes:, prompt:, persona: nil)
    Rails.logger.info "🎪 Starting performance mode job for session #{session_id}"

    begin
      # Create service instance
      service = PerformanceModeService.new(
        session_id: session_id,
        performance_type: performance_type,
        duration_minutes: duration_minutes,
        prompt: prompt,
        persona: persona
      )

      # Set running state
      service.instance_variable_set(:@start_time, Time.current)
      service.instance_variable_set(:@end_time, Time.current + duration_minutes.minutes)
      service.instance_variable_set(:@is_running, true)
      service.instance_variable_set(:@should_stop, false)
      service.instance_variable_set(:@performance_segments, [])

      # Store initial state
      service.send(:store_performance_state)

      # Run the performance loop
      service.run_performance_loop

      Rails.logger.info "✅ Performance mode job completed for session #{session_id}"

    rescue => e
      Rails.logger.error "❌ Performance mode job failed: #{e.message}"
      Rails.logger.error e.backtrace.first(10)

      # Try to clean up state
      begin
        Rails.cache.delete("performance_mode:#{session_id}")
      rescue
        # Ignore cleanup errors
      end
    end
  end
end
