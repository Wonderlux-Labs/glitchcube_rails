# frozen_string_literal: true

# SolidQueue configuration
Rails.application.configure do
  # Configure SolidQueue to use separate database and logging
  if Rails.env.development? || Rails.env.production?
    config.after_initialize do
      if defined?(SolidQueue)
        # Create separate logger for SolidQueue
        solid_queue_logger = ActiveSupport::Logger.new(
          Rails.root.join("log", "solid_queue.log"),
          1, # Keep 1 old log file
          10.megabytes # Rotate at 10MB
        )

        solid_queue_logger.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity} -- #{progname}: #{msg}\n"
        end

        # Set SolidQueue to use the separate logger
        SolidQueue.logger = solid_queue_logger

        # Ensure SolidQueue models use the queue database connection
        SolidQueue::Record.connects_to database: { writing: :queue, reading: :queue }
      end
    end
  end
end
