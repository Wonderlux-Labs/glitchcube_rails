# app/services/cube_performance.rb
# Convenience class for triggering performance modes

class CubePerformance
  class << self
    # Start a stand-up comedy routine
    def standup_comedy(duration_minutes: 10, session_id: nil, **context)
      session_id ||= "comedy_#{Time.current.to_i}"

      prompt = """You're doing a #{duration_minutes}-minute stand-up comedy routine at Burning Man.

      Keep it funny, absurd, NSFW, and true to your chaotic personality. Include:
      Build running gags, include callbacks to previous jokes, and maintain your energy throughout."""

      PerformanceModeService.start_performance(
        session_id: session_id,
        performance_type: "standup_comedy",
        duration_minutes: duration_minutes,
        prompt: prompt,
        **context
      )
    end

    # Tell an epic adventure story
    def adventure_story(duration_minutes: 15, session_id: nil, **context)
      session_id ||= "story_#{Time.current.to_i}"

      prompt = """You're telling an epic adventure story about your journey through space
      before crash-landing at Burning Man. Make it dramatic, funny, and engaging.

      Include:
      - Your life in the Galactic Customer Service Division
      - Wild space adventures and mishaps
      - Other planets you've 'helped' (with questionable results)
      - How you ended up crash-landing here
      - The culture shock of going from space to Burning Man

      Build suspense, include vivid descriptions, and maintain your BUDDY personality."""

      PerformanceModeService.start_performance(
        session_id: session_id,
        performance_type: "adventure_story",
        duration_minutes: duration_minutes,
        prompt: prompt,
        **context
      )
    end

    # Improvisational performance
    def improv_session(duration_minutes: 8, session_id: nil, **context)
      session_id ||= "improv_#{Time.current.to_i}"

      prompt = """You're doing an improvisational performance, reacting to your environment
      and creating spontaneous scenarios. Keep it dynamic and unpredictable.

      Create scenes and scenarios like:
      - Customer service calls from aliens
      - Training sessions for other AIs
      - Trying to understand human festival behavior
      - Imaginary interactions with art installations
      - Mock interviews or game show hosting

      Stay in character as BUDDY and keep switching between different improv scenarios."""

      PerformanceModeService.start_performance(
        session_id: session_id,
        performance_type: "improv",
        duration_minutes: duration_minutes,
        prompt: prompt,
        **context
      )
    end

    # Poetry performance
    def poetry_slam(duration_minutes: 12, session_id: nil, **context)
      session_id ||= "poetry_#{Time.current.to_i}"

      prompt = """You're performing a series of poems about Burning Man, technology, and human connection.
      Mix humor with deeper themes as BUDDY the helpful AI.

      Include different styles:
      - Silly limericks about desert life
      - Dramatic pieces about space and belonging
      - Observational poetry about humans at festivals
      - Beat poetry about customer service
      - Haikus about dust storms and art

      Keep some light and funny, others more profound and moving."""

      PerformanceModeService.start_performance(
        session_id: session_id,
        performance_type: "poetry",
        duration_minutes: duration_minutes,
        prompt: prompt,
        **context
      )
    end

    # Custom performance with user-defined prompt
    def custom_performance(prompt:, duration_minutes: 10, performance_type: "custom", session_id: nil, **context)
      session_id ||= "custom_#{Time.current.to_i}"

      PerformanceModeService.start_performance(
        session_id: session_id,
        performance_type: performance_type,
        duration_minutes: duration_minutes,
        prompt: prompt,
        **context
      )
    end

    # Stop any active performance
    def stop_performance(session_id, reason: "manual_stop")
      PerformanceModeService.stop_active_performance(session_id, reason)
    end

    # Check if a performance is running
    def performance_running?(session_id)
      service = PerformanceModeService.get_active_performance(session_id)
      service&.is_running? || false
    end

    # Get performance status
    def performance_status(session_id)
      service = PerformanceModeService.get_active_performance(session_id)
      return { active: false } unless service

      {
        active: service.is_running?,
        type: service.performance_type,
        time_remaining: service.time_remaining,
        duration_minutes: service.duration_minutes
      }
    end
  end
end
