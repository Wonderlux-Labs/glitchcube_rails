# frozen_string_literal: true

module Jobs
  class ToolExecutionWorker
    include Sidekiq::Worker

    # Configure Sidekiq options
    sidekiq_options retry: 3, dead: true

    def perform(actions, session_id, original_message)
      # Setup dependencies needed for the job
      logger = $logger
      action_extractor = ::Services::Conversation::ActionExtractor.new(logger: logger)
      state_manager = ::Services::Conversation::StateManager.new

      logger.info('🔥 Sidekiq tool execution worker started',
                  tagged: %i[sidekiq tools worker_start],
                  job_id: jid,
                  session_id: session_id,
                  action_count: actions.count)

      begin
        # Execute the tools via Claude conversation agent
        results = action_extractor.execute_actions_via_claude(
          actions,
          session_id,
          original_message
        )

        # Get the session and add results to conversation history as system message
        session = ConversationSession.find_or_create(session_id: session_id)
        if session
          history_message = if results[:success]
                              "[System: Background actions completed successfully. #{results[:message]}]"
                            else
                              "[System: Background actions FAILED. #{results[:message]}]"
                            end

          state_manager.record_message(
            session: session,
            role: 'system',
            content: history_message,
            persona: 'system'
          )
        else
          logger.warn('⚠️ Could not find session to record tool results',
                      tagged: %i[sidekiq tools session_error],
                      session_id: session_id)
        end

        logger.info('✅ Sidekiq tool execution completed successfully',
                    tagged: %i[sidekiq tools worker_success],
                    job_id: jid,
                    session_id: session_id,
                    success: results[:success],
                    message: results[:message]&.[](0..100))

        # Store failure info for next conversation turn if needed
        unless results[:success]
          store_tool_failure(session_id, results[:message])
        end
      rescue StandardError => e
        logger.error('💥 Sidekiq tool execution worker failed',
                     tagged: %i[sidekiq tools worker_error],
                     job_id: jid,
                     session_id: session_id,
                     error: e.message,
                     backtrace: e.backtrace&.first(3))

        # Add failure to history so the persona knows about it
        failure_message = "[System: Background actions FAILED with error. #{e.message}]"
        begin
          session = ConversationSession.find_or_create(session_id: session_id)
          if session
            state_manager.record_message(
              session: session,
              role: 'system',
              content: failure_message,
              persona: 'system'
            )
          end
          store_tool_failure(session_id, e.message)
        rescue StandardError => history_error
          logger.error('💥 Failed to record tool failure to history',
                       tagged: %i[sidekiq tools history_error],
                       job_id: jid,
                       session_id: session_id,
                       error: history_error.message)
        end

        # Re-raise to let Sidekiq handle retry logic
        raise
      end
    end

    private

    def store_tool_failure(session_id, message)
      # Store in Redis for next conversation turn

      redis = Redis.new(url: GlitchCube.config.redis_url)
      redis.setex("tool_failure:#{session_id}", 300, message) # 5 minute expiry

      Services::Logging::SimpleLogger.debug('📋 Stored tool failure for next conversation',
                                            tagged: %i[sidekiq tools failure_storage],
                                            session_id: session_id,
                                            message: message[0..50])
    rescue StandardError => e
      Services::Logging::SimpleLogger.warn('⚠️ Could not store tool failure in Redis',
                                           tagged: %i[sidekiq tools redis_error],
                                           session_id: session_id,
                                           error: e.message)
    end
  end
end
