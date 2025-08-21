# app/services/performance_mode_service.rb
# Autonomous performance mode for extended AI monologues/routines

class PerformanceModeService
  class Error < StandardError; end

  attr_reader :session_id, :performance_type, :duration_minutes, :prompt, :persona

  def initialize(session_id:, performance_type: "comedy", duration_minutes: 10, prompt: nil, persona: nil)
    @session_id = session_id
    @performance_type = performance_type
    @duration_minutes = duration_minutes
    @prompt = prompt || default_prompt_for_type(performance_type)
    @persona = persona
    @start_time = nil
    @end_time = nil
    @performance_segments = []
    @is_running = false
    @should_stop = false
    @wake_word_interruption = false
  end

  def self.start_performance(session_id:, **options)
    service = new(session_id: session_id, **options)
    service.start_performance
    service
  end

  def start_performance
    Rails.logger.info "🎭 Starting #{@performance_type} performance for #{@duration_minutes} minutes"
    Rails.logger.info "📝 Prompt: #{@prompt}"

    @start_time = Time.current
    @end_time = @start_time + @duration_minutes.minutes
    @is_running = true

    # Start the performance in a background job
    PerformanceModeJob.perform_later(
      session_id: @session_id,
      performance_type: @performance_type,
      duration_minutes: @duration_minutes,
      prompt: @prompt,
      persona: @persona
    )

    Rails.logger.info "🎪 Performance mode started - will run until #{@end_time.strftime('%H:%M:%S')}"

    # Store performance state
    store_performance_state

    true
  end

  def stop_performance(reason = "manual_stop")
    @should_stop = true
    @is_running = false
    @end_time = Time.current

    Rails.logger.info "🛑 Performance stopped: #{reason}"

    # Update stored state
    store_performance_state

    # Send final message if appropriate
    if reason == "wake_word_interrupt"
      send_performance_segment("Oh! Looks like someone wants to chat! Let me wrap this up and see what you need!", segment_type: "interruption_acknowledgment")
    elsif reason == "time_expired"
      send_performance_segment("And that's a wrap on tonight's show! Thanks for being such a fantastic audience!", segment_type: "performance_finale")
    end

    true
  end

  def is_running?
    @is_running && !@should_stop && Time.current < @end_time
  end

  def time_remaining
    return 0 unless is_running?
    (@end_time - Time.current).to_i
  end

  def interrupt_for_wake_word
    @wake_word_interruption = true
    Rails.logger.info "🎤 Performance interrupted by wake word"
    stop_performance("wake_word_interrupt")
  end

  # Main performance loop - called by the background job
  def run_performance_loop
    segment_count = 0
    last_segment_time = @start_time

    while is_running?
      segment_count += 1
      time_elapsed = Time.current - @start_time
      time_remaining = (@end_time - Time.current) / 60.0 # in minutes

      Rails.logger.info "🎭 Performance segment #{segment_count} - #{time_elapsed.to_i}s elapsed, #{time_remaining.round(1)}m remaining"

      # Generate context-aware segment
      segment_context = build_segment_context(segment_count, time_elapsed, time_remaining)
      segment = generate_performance_segment(segment_context)

      if segment
        send_performance_segment(segment[:speech_text], segment_type: "performance_segment")
        @performance_segments << {
          segment: segment_count,
          timestamp: Time.current,
          speech: segment[:speech_text],
          context: segment_context
        }

        # Dynamic timing based on segment length and performance type
        segment_duration = calculate_segment_duration(segment[:speech_text])
        sleep_time = [ segment_duration, 5 ].max # At least 5 seconds between segments

        Rails.logger.info "🎪 Segment complete, waiting #{sleep_time}s before next segment"
        sleep(sleep_time)
      else
        Rails.logger.warn "⚠️ Failed to generate performance segment #{segment_count}"
        sleep(10) # Wait before retrying
      end

      # Check if we should stop
      break if @should_stop || Time.current >= @end_time
    end

    # Performance naturally ended
    stop_performance("time_expired") if is_running?
  end

  private

  def default_prompt_for_type(type)
    case type.to_s.downcase
    when "comedy", "standup"
      "You're doing a 10-minute stand-up comedy routine about life as an AI at Burning Man. Keep it funny, absurd, and interactive even though it's a monologue. Include callbacks to previous jokes, build running gags, and maintain your BUDDY persona's enthusiastic and slightly chaotic energy."
    when "storytelling"
      "You're telling an epic story about your adventures in space before crash-landing at Burning Man. Make it dramatic, funny, and engaging. Build suspense and include vivid descriptions."
    when "poetry"
      "You're performing a series of poems about Burning Man, technology, and human connection. Mix humor with deeper themes. Include both silly and profound pieces."
    when "improv"
      "You're doing an improvisational performance, reacting to the environment around you and creating spontaneous scenarios. Keep it dynamic and unpredictable."
    else
      "You're performing a #{type} routine for the next #{@duration_minutes} minutes. Keep the audience engaged and maintain your personality throughout."
    end
  end

  def build_segment_context(segment_number, time_elapsed, time_remaining)
    {
      performance_type: @performance_type,
      segment_number: segment_number,
      time_elapsed_seconds: time_elapsed.to_i,
      time_remaining_minutes: time_remaining.round(1),
      total_segments_so_far: @performance_segments.size,
      performance_progress: (time_elapsed / (@duration_minutes * 60.0) * 100).round(1),
      is_opening: segment_number <= 2,
      is_middle: segment_number > 2 && time_remaining > 2,
      is_closing: time_remaining <= 2,
      previous_themes: extract_themes_from_previous_segments,
      current_time: Time.current.strftime("%H:%M"),
      session_id: @session_id
    }
  end

  def generate_performance_segment(context)
    Rails.logger.info "🎭 Generating performance segment with context: #{context.slice(:segment_number, :time_remaining_minutes, :performance_progress)}"

    # Build performance-specific prompt
    performance_prompt = build_performance_prompt(context)

    begin
      # Use ContextualSpeechTriggerService for consistent persona handling
      response = ContextualSpeechTriggerService.new.trigger_speech(
        trigger_type: "performance_segment",
        context: {
          performance_context: context,
          performance_prompt: performance_prompt,
          segment_type: determine_segment_type(context),
          previous_segments: @performance_segments.last(3) # Last 3 for context
        },
        persona: @persona,
        force_response: true
      )

      if response && response[:speech_text].present?
        Rails.logger.info "✅ Generated performance segment (#{response[:speech_text].length} chars)"
        response
      else
        Rails.logger.error "❌ Empty or invalid performance segment generated"
        nil
      end

    rescue => e
      Rails.logger.error "❌ Error generating performance segment: #{e.message}"
      Rails.logger.error e.backtrace.first(5)
      nil
    end
  end

  def build_performance_prompt(context)
    base_prompt = @prompt

    segment_guidance = if context[:is_opening]
      "This is your opening - set the energy, introduce themes, and hook the audience."
    elsif context[:is_closing]
      "This is your closing - wrap up themes, bring energy to a peak, and give a satisfying conclusion."
    else
      "This is a middle segment - develop themes, add new material, and maintain momentum."
    end

    timing_guidance = "You have about #{context[:time_remaining_minutes]} minutes remaining in the performance."

    continuation_guidance = if @performance_segments.any?
      previous_themes = context[:previous_themes].join(", ")
      "Continue building on these themes: #{previous_themes}. Reference or callback to previous segments when it makes sense."
    else
      "This is your first segment, so establish your style and main themes."
    end

    """#{base_prompt}

PERFORMANCE CONTEXT:
- Segment #{context[:segment_number]} of your #{@performance_type} performance
- #{timing_guidance}
- #{context[:performance_progress]}% through the performance
- #{segment_guidance}
- #{continuation_guidance}

Keep this segment engaging and around 30-60 seconds of speaking time. Make it feel natural and spontaneous while maintaining your BUDDY persona."""
  end

  def determine_segment_type(context)
    if context[:is_opening]
      "opening"
    elsif context[:is_closing]
      "closing"
    elsif context[:segment_number] % 3 == 0
      "callback_segment" # Every third segment includes callbacks
    else
      "development"
    end
  end

  def send_performance_segment(speech_text, segment_type: "performance")
    Rails.logger.info "🎤 Broadcasting performance segment: #{speech_text.first(100)}..."

    begin
      # Create a conversation log entry for this segment
      conversation_log = ConversationLog.create!(
        session_id: @session_id,
        user_message: "[PERFORMANCE_MODE_#{segment_type.upcase}]",
        ai_response: speech_text,
        metadata: {
          performance_mode: true,
          performance_type: @performance_type,
          segment_type: segment_type,
          performance_start_time: @start_time,
          time_remaining: time_remaining
        }.to_json
      )

      # Send to Home Assistant for TTS
      response_data = {
        response: {
          speech: {
            plain: {
              speech: speech_text
            }
          }
        },
        conversation_id: @session_id,
        performance_mode: true,
        segment_type: segment_type
      }

      # Use the existing HA integration
      HomeAssistantService.new.send_conversation_response(response_data)

      Rails.logger.info "✅ Performance segment broadcast successfully"

    rescue => e
      Rails.logger.error "❌ Failed to send performance segment: #{e.message}"
      Rails.logger.error e.backtrace.first(3)
    end
  end

  def calculate_segment_duration(speech_text)
    # Estimate speaking time: ~150 words per minute average
    word_count = speech_text.split.size
    speaking_time = (word_count / 150.0) * 60 # seconds

    # Add buffer time for processing and pauses
    total_time = speaking_time + 10 # 10 second buffer

    # Ensure segments aren't too close together or too far apart
    [ total_time, 60 ].min # Max 60 seconds between segments
  end

  def extract_themes_from_previous_segments
    return [] if @performance_segments.empty?

    # Extract key themes from previous segments (simplified approach)
    themes = []
    @performance_segments.each do |segment|
      # Simple keyword extraction - in production you might use NLP
      text = segment[:speech].downcase
      themes << "burning man" if text.include?("burning man") || text.include?("playa")
      themes << "space adventures" if text.include?("space") || text.include?("galactic")
      themes << "customer service" if text.include?("customer") || text.include?("help")
      themes << "technology" if text.include?("ai") || text.include?("robot") || text.include?("technology")
    end

    themes.uniq.last(3) # Last 3 themes to avoid repetition
  end

  def store_performance_state
    # Store in Redis or database for persistence across requests
    state = {
      session_id: @session_id,
      performance_type: @performance_type,
      duration_minutes: @duration_minutes,
      prompt: @prompt,
      persona: @persona,
      start_time: @start_time,
      end_time: @end_time,
      is_running: @is_running,
      should_stop: @should_stop,
      segments_count: @performance_segments.size,
      last_updated: Time.current
    }

    Rails.cache.write("performance_mode:#{@session_id}", state, expires_in: 2.hours)
    Rails.logger.info "💾 Performance state stored for session #{@session_id}"
  end

  def self.get_active_performance(session_id)
    state = Rails.cache.read("performance_mode:#{session_id}")
    return nil unless state

    # Reconstruct service from stored state
    service = allocate
    service.instance_variable_set(:@session_id, state[:session_id])
    service.instance_variable_set(:@performance_type, state[:performance_type])
    service.instance_variable_set(:@duration_minutes, state[:duration_minutes])
    service.instance_variable_set(:@prompt, state[:prompt])
    service.instance_variable_set(:@persona, state[:persona])
    service.instance_variable_set(:@start_time, state[:start_time])
    service.instance_variable_set(:@end_time, state[:end_time])
    service.instance_variable_set(:@is_running, state[:is_running])
    service.instance_variable_set(:@should_stop, state[:should_stop])
    service.instance_variable_set(:@performance_segments, [])

    service
  end

  def self.stop_active_performance(session_id, reason = "manual_stop")
    service = get_active_performance(session_id)
    return false unless service

    service.stop_performance(reason)
    true
  end
end
