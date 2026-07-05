# frozen_string_literal: true

# SolidQueue logging & database wiring.
#
# The point of this file: keep `log/development.log` READABLE. SolidQueue polls,
# claims, and finishes jobs constantly, and the recurring system jobs fire every
# minute — left alone, that firehose of framework lines and SQL drowns out the
# actual request/conversation activity you're trying to tail. So we push all of
# that noise into a dedicated `log/solid_queue.log`:
#
#   1. SolidQueue's own supervisor/dispatcher/worker logs  -> SolidQueue.logger
#   2. ActiveJob framework lines (Enqueued/Performing/…)    -> config.active_job.logger
#   3. Every SQL statement issued from inside a job         -> dropped from the AR logger
#
# What STAYS in development.log: web-request SQL, and any `Rails.logger.*` calls
# your jobs make directly (the 🎬/🏠 emoji breadcrumbs) — those are the useful
# bits, and they keep flowing.

Rails.application.configure do
  next unless Rails.env.development? || Rails.env.production?

  solid_queue_logger = ActiveSupport::Logger.new(
    Rails.root.join("log", "solid_queue.log"),
    1,             # keep 1 rotated file
    10.megabytes   # rotate at 10MB
  )
  solid_queue_logger.formatter = proc do |severity, datetime, progname, msg|
    "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity} -- #{progname}: #{msg}\n"
  end

  # (2) Move ActiveJob's own chatter (Enqueued/Performing/Performed) off Rails.logger.
  config.active_job.logger = solid_queue_logger

  config.after_initialize do
    if defined?(SolidQueue)
      # (1) SolidQueue's operational logs.
      SolidQueue.logger = solid_queue_logger

      # SolidQueue models live in the queue database.
      SolidQueue::Record.connects_to database: { writing: :queue, reading: :queue }
    end
  end
end

# (3) Drop SQL echo that originates from background jobs. query_log_tags are
# enabled (see development.rb), so job-issued SQL — including SolidQueue's own
# table churn and the bare TRANSACTION BEGIN/COMMIT statements — carries a
# `job=...` comment. Anything touching a solid_queue_* table gets dropped too,
# covering the supervisor's polling/claim/insert traffic that runs outside a job.
module SilenceBackgroundJobSql
  def sql(event)
    sql = event.payload[:sql].to_s
    name = event.payload[:name].to_s
    return if name.start_with?("SolidQueue")
    return if sql.include?("solid_queue_")
    return if sql.include?("job=") # query-log tag -> came from inside a job

    super
  end
end
ActiveSupport.on_load(:active_record) do
  ActiveRecord::LogSubscriber.prepend(SilenceBackgroundJobSql)
end
