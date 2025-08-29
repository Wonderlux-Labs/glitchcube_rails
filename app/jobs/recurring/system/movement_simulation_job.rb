class Recurring::System::MovementSimulationJob < ApplicationJob
  queue_as :default

  def perform
    # Check if there's an active movement
    gps_service = Gps::GpsTrackingService.new
    movement_status = gps_service.movement_status

    if movement_status[:is_moving]
      # Perform a single movement step
      result = gps_service.simulate_movement!

      if result[:success]
        Rails.logger.info "Movement simulation step completed: #{result[:message]}"

        # Schedule the next step
        self.class.set(wait: 5.seconds).perform_later
      else
        Rails.logger.error "Movement simulation failed: #{result[:message]}"
      end
    else
      Rails.logger.info "No active movement, skipping simulation"
    end
  rescue => e
    Rails.logger.error "Movement simulation job failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
end
