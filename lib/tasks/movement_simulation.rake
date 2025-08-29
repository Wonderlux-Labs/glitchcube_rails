namespace :movement do
  desc "Test the movement simulation by triggering a single step"
  task test: :environment do
    puts "Testing movement simulation..."

    gps_service = Gps::GpsTrackingService.new

    # Check current status
    status = gps_service.movement_status
    puts "Current movement status:"
    puts "  Moving: #{status[:is_moving]}"
    puts "  Destination: #{status[:destination] || 'None'}"
    puts "  Distance remaining: #{status[:distance_remaining] || 'N/A'}"

    # Start movement if not already moving
    unless status[:is_moving]
      puts "\nStarting movement to random destination..."
      result = gps_service.simulate_movement!
      puts "  #{result[:message]}"

      # Check status again
      status = gps_service.movement_status
      puts "\nNew movement status:"
      puts "  Moving: #{status[:is_moving]}"
      puts "  Destination: #{status[:destination] || 'None'}"
      puts "  Distance remaining: #{status[:distance_remaining] || 'N/A'}"
    else
      puts "\nAlready moving, performing next step..."
      result = gps_service.simulate_movement!
      puts "  #{result[:message]}"
    end

    puts "\nTest complete!"
  end

  desc "Start continuous movement simulation background job"
  task start: :environment do
    puts "Starting continuous movement simulation..."

    # Clear any existing destination
    Rails.cache.delete("cube_destination")

    # Start the movement
    gps_service = Gps::GpsTrackingService.new
    result = gps_service.simulate_movement!

    if result[:success]
      puts "Movement started: #{result[:message]}"
      puts "Background job will continue the movement automatically."
    else
      puts "Failed to start movement: #{result[:message]}"
    end
  end

  desc "Stop all movement"
  task stop: :environment do
    puts "Stopping all movement..."

    gps_service = Gps::GpsTrackingService.new
    result = gps_service.stop_movement

    puts result[:message]
  end

  desc "Set destination to specific landmark"
  task :set_destination, [ :landmark ] => :environment do |t, args|
    landmark_name = args[:landmark]

    if landmark_name.blank?
      puts "Usage: rake movement:set_destination[landmark_name]"
      puts "Available landmarks:"

      landmarks = Landmark.active.order(:name)
      landmarks.each do |landmark|
        puts "  - #{landmark.name} (#{landmark.landmark_type})"
      end
      next
    end

    puts "Setting destination to: #{landmark_name}"

    gps_service = Gps::GpsTrackingService.new
    result = gps_service.set_destination(landmark_name)

    puts result[:message]
    if result[:success]
      puts "Movement will start automatically via background job."
    end
  end
end
