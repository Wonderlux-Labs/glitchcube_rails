class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # Pin every job's ActiveRecord queries to the PRIMARY writing connection.
  #
  # We run SolidQueue in its own process with the queue tables on a SEPARATE
  # database (`config.solid_queue.connects_to = { database: { writing: :queue } }`).
  # In that long-running worker, the thread-local connection role/context
  # intermittently leaked, so plain `ApplicationRecord` models (Conversation,
  # Persona, …) would resolve onto the queue pool — `PG::UndefinedTable:
  # relation "conversations" does not exist` — or onto no pool at all —
  # `ActiveRecord::ConnectionNotDefined: No database connection defined`. It hit
  # the recurring jobs hardest (ConversationStatsJob, RandomPersonaJob), silently
  # disabling stats pushes and cron persona rotation.
  #
  # Forcing the writing role for the whole perform makes app-model queries always
  # resolve to `primary`, immune to whatever the worker thread's ambient context
  # was. SolidQueue's own records live on their own connection class, so this
  # doesn't touch queue bookkeeping.
  around_perform do |job, block|
    # TEMP DIAGNOSTIC (revert): confirm the wrapper runs and log connection context.
    if job.class.name == "Recurring::System::ConversationStatsJob"
      Rails.logger.warn("🔎AJWRAP before: role=#{ActiveRecord::Base.current_role} " \
        "shard=#{ActiveRecord::Base.current_shard} " \
        "arbase-pool=#{ActiveRecord::Base.connection_pool.db_config.name}/#{ActiveRecord::Base.connection_pool.db_config.database} " \
        "conv-spec=#{Conversation.connection_specification_name}")
    end
    ActiveRecord::Base.connected_to(role: ActiveRecord.writing_role) { block.call }
  end
end
