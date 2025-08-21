# Performance Mode Documentation

Performance Mode allows the Glitch Cube to autonomously generate and deliver extended monologues, routines, and performances while remaining responsive to wake word interruptions for normal conversation.

## Overview

Performance Mode is designed for scenarios where the cube needs to entertain or engage an audience for extended periods (5-20+ minutes) without constant user interaction. Perfect for:

- Stand-up comedy routines at events
- Storytelling sessions
- Poetry performances  
- Improvisational entertainment
- Custom themed performances

## Architecture

### Core Components

- **PerformanceModeService**: Main service managing performance lifecycle
- **PerformanceModeJob**: Background job running the autonomous performance loop
- **CubePerformance**: Convenience wrapper for common performance types
- **ContextualSpeechTriggerService**: Generates contextual performance segments
- **Performance Controllers**: API and web interfaces for control

### Flow Diagram

```
User/API Request → PerformanceModeService.start_performance()
                ↓
           PerformanceModeJob (background)
                ↓
    Autonomous Loop: Generate segments every 30-60s
                ↓
    ContextualSpeechTriggerService → LLM → Speech Generation
                ↓
         Broadcast via HomeAssistant TTS
                ↓
    Continue until: Time expires OR Wake word interruption
```

## Usage

### Quick Start

```ruby
# Start a 10-minute comedy routine
CubePerformance.standup_comedy(duration_minutes: 10)

# Start adventure storytelling  
CubePerformance.adventure_story(duration_minutes: 15)

# Check if performance is running
CubePerformance.performance_running?('session_id')

# Stop performance
CubePerformance.stop_performance('session_id')
```

### API Usage

#### Start Performance
```bash
curl -X POST "http://localhost:3000/api/v1/performance_mode/start" \
  -H "Content-Type: application/json" \
  -H "X-Session-ID: my_session" \
  -d '{
    "performance_type": "standup_comedy",
    "duration_minutes": 10,
    "prompt": "Custom prompt (optional)"
  }'
```

#### Check Status
```bash
curl -X GET "http://localhost:3000/api/v1/performance_mode/status" \
  -H "X-Session-ID: my_session"
```

#### Stop Performance
```bash
curl -X POST "http://localhost:3000/api/v1/performance_mode/stop" \
  -H "X-Session-ID: my_session"
```

### Web Interface

Visit `/performance` for a user-friendly interface to:
- Start different performance types
- Monitor active performances
- Stop performances manually

## Performance Types

### 1. Stand-up Comedy (`standup_comedy`)
- **Duration**: 5-20 minutes typical
- **Style**: Humorous routine about AI life at Burning Man
- **Features**: Running gags, callbacks, interactive elements
- **Persona**: BUDDY's enthusiastic customer service energy

### 2. Adventure Story (`adventure_story`)  
- **Duration**: 10-25 minutes typical
- **Style**: Epic narrative about space adventures before crash-landing
- **Features**: Suspense building, vivid descriptions, character development
- **Persona**: BUDDY's space travel background

### 3. Improv Session (`improv`)
- **Duration**: 5-15 minutes typical  
- **Style**: Spontaneous scenes and scenarios
- **Features**: Dynamic scenario switching, character voices, audience interaction
- **Persona**: BUDDY's adaptable nature

### 4. Poetry Slam (`poetry`)
- **Duration**: 8-20 minutes typical
- **Style**: Mix of humorous and profound poetry
- **Features**: Various poetry styles, thematic progression, emotional range
- **Persona**: BUDDY's creative expression

### 5. Custom Performance
```ruby
CubePerformance.custom_performance(
  prompt: "Your custom performance instructions here",
  duration_minutes: 12,
  performance_type: 'my_custom_type'
)
```

## Configuration

### Performance Segments
- **Segment Length**: 30-60 seconds of speaking time
- **Segment Interval**: Dynamic based on content length + 10s buffer
- **Context Awareness**: Each segment builds on previous themes
- **Progress Tracking**: Opening → Middle → Closing segments

### Wake Word Integration
- Performance automatically pauses when wake word detected
- Graceful transition: "Oh! Looks like someone wants to chat!"
- Resumes normal conversation mode
- Performance state cleaned up automatically

### State Management
- Performance state stored in Rails.cache (Redis recommended)
- Persists across application restarts
- 2-hour expiration for cleanup
- Session-based isolation

## Technical Details

### Background Job Processing
```ruby
class PerformanceModeJob < ApplicationJob
  queue_as :default
  
  def perform(session_id:, performance_type:, duration_minutes:, prompt:, persona: nil)
    # Creates service instance and runs performance loop
  end
end
```

### Segment Generation
Uses ContextualSpeechTriggerService with performance-specific prompts:

```ruby
def generate_performance_segment(context)
  response = ContextualSpeechTriggerService.new.trigger_speech(
    trigger_type: 'performance_segment',
    context: {
      performance_context: context,
      performance_prompt: performance_prompt,
      segment_type: determine_segment_type(context),
      previous_segments: @performance_segments.last(3)
    },
    persona: @persona,
    force_response: true
  )
end
```

### Home Assistant Integration
Performance segments broadcast through existing HA integration:

```ruby
# Creates conversation log entries
ConversationLog.create!(
  session_id: @session_id,
  user_message: "[PERFORMANCE_MODE_#{segment_type.upcase}]",
  ai_response: speech_text,
  metadata: performance_metadata.to_json
)

# Sends to HA for TTS
HomeAssistantService.new.send_conversation_response(response_data)
```

## Monitoring & Debugging

### Log Patterns
```
🎭 Starting standup_comedy performance for 10 minutes
🎪 Performance mode started - will run until 14:35:22
🎭 Performance segment 1 - 30s elapsed, 9.5m remaining
🎤 Broadcasting performance segment: Oh fuck yeah! Let me tell you about...
✅ Performance segment broadcast successfully
🛑 Performance stopped: wake_word_interrupt
```

### Performance Metrics
- Segment generation success/failure rates
- Average segment length and timing
- Performance completion rates
- Wake word interruption frequency

### Common Issues

**Performance doesn't start:**
- Check background job processing is enabled
- Verify Rails.cache is configured (Redis recommended)
- Check LLM service connectivity

**Segments not generating:**
- Review ContextualSpeechTriggerService logs
- Verify persona prompts are loading correctly
- Check for LLM rate limiting

**Wake word interruption not working:**
- Ensure ConversationOrchestrator integration is active
- Verify session ID consistency across systems
- Check performance state persistence

## Testing

### Manual Testing
```bash
# Run basic functionality test
ruby scripts/test_performance_mode.rb

# Test API endpoints (requires Rails server running)
ruby scripts/test_performance_mode.rb --api
```

### Automated Testing
Performance mode includes comprehensive test coverage:
- Unit tests for PerformanceModeService
- Integration tests for background job processing  
- API endpoint testing with VCR cassettes
- Wake word interruption scenarios

## Security Considerations

- Session ID validation prevents cross-session interference
- Performance duration limits prevent resource exhaustion
- Automatic cleanup prevents stale state accumulation
- Content filtering through existing persona constraints

## Future Enhancements

- **Audience Interaction**: Integration with sensor data for crowd response
- **Dynamic Adjustment**: Real-time performance modification based on engagement
- **Performance Analytics**: Detailed metrics and performance optimization
- **Multi-Modal**: Integration with lighting and visual effects during performances
- **Collaborative**: Multi-agent performances with different personas