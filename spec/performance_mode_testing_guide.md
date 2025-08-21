# Performance Mode VCR Testing Suite

This guide covers the comprehensive VCR integration test suite for the Performance Mode system.

## Test Structure

### Core Component Tests

#### 1. PerformanceModeService (`spec/services/performance_mode_service_spec.rb`)
- **Happy path workflows**: Start → Generate segments → Complete naturally
- **Wake word interruption**: Mid-performance interrupt → Clean shutdown
- **Error scenarios**: LLM failures, HA connectivity issues, malformed responses
- **State management**: Performance persistence, cache operations
- **Different performance types**: Comedy, storytelling, improv, poetry
- **Edge cases**: Very short/long durations, timing validation

**Key VCR Cassettes:**
- `performance_mode/start_performance`
- `performance_mode/stop_performance`
- `performance_mode/wake_word_interrupt`
- `performance_mode/performance_loop`
- `performance_mode/generate_segment`

#### 2. PerformanceModeJob (`spec/jobs/performance_mode_job_spec.rb`)
- **Background processing**: Realistic timing with controlled speed-up
- **Error handling**: Service failures, cleanup operations
- **Concurrent execution**: Multiple jobs running simultaneously  
- **Resource management**: Memory leak prevention
- **Job monitoring**: Logging and observability

**Key VCR Cassettes:**
- `performance_mode_job/successful_performance`
- `performance_mode_job/error_handling`
- `performance_mode_job/integration_test`
- `performance_mode_job/concurrent_types`

#### 3. PerformanceModeController (`spec/requests/performance_mode_spec.rb`)
- **API endpoints**: All CRUD operations via HTTP
- **Session handling**: Headers vs parameters
- **Error responses**: Proper HTTP status codes
- **Concurrent sessions**: Multiple independent performances
- **Complete workflows**: Start → Status → Interrupt/Stop → Status

**Key VCR Cassettes:**
- `performance_mode_api/start_performance`
- `performance_mode_api/stop_performance`
- `performance_mode_api/status_check`
- `performance_mode_api/interrupt_performance`

#### 4. CubePerformance (`spec/services/cube_performance_spec.rb`)
- **Convenience methods**: All performance types with appropriate prompts
- **Parameter handling**: Custom durations, session IDs, personas
- **State management**: Running status, stop operations
- **Integration**: Delegation to PerformanceModeService

**Key VCR Cassettes:**
- `cube_performance/standup_comedy`
- `cube_performance/adventure_story`
- `cube_performance/improv_session`
- `cube_performance/poetry_slam`

### Integration Tests

#### 5. LLM Integration (`spec/integration/performance_mode_llm_integration_spec.rb`)
- **ContextualSpeechTriggerService integration**: LLM calls for segment generation
- **Prompt construction**: Performance-specific contexts and personas
- **Error handling**: LLM failures, timeouts, malformed responses
- **Response validation**: Content quality and structure checks
- **Real-time scenarios**: Segment continuity and context building

**Key VCR Cassettes:**
- `performance_llm/contextual_speech_integration`
- `performance_llm/response_processing`
- `performance_llm/realtime_scenarios`

#### 6. State Management (`spec/integration/performance_mode_state_management_spec.rb`)
- **Cache persistence**: State storage and retrieval
- **Concurrent sessions**: Independent session management
- **Error recovery**: Cache failures, corrupted state handling
- **Resource cleanup**: Memory leak prevention, orphaned entries
- **Monitoring**: System-wide metrics and health checks

**Key VCR Cassettes:**
- `performance_state/persistence`
- `performance_state/concurrent_sessions`
- `performance_state/error_recovery`
- `performance_state/monitoring`

#### 7. End-to-End Integration (`spec/integration/performance_mode_end_to_end_spec.rb`)
- **Complete workflows**: Full API → Job → LLM → HA integration
- **Error scenarios**: Service failures at each integration point
- **Concurrent performances**: Multiple sessions with different types
- **Realistic timing**: Proportional delays with controlled speed-up
- **Mixed interfaces**: API + CubePerformance integration

**Key VCR Cassettes:**
- `performance_e2e/complete_workflow`
- `performance_e2e/error_scenarios`
- `performance_e2e/concurrent_performances`

## Running the Tests

### Prerequisites
```bash
# Ensure VCR cassettes are recorded with real API responses
export OPENROUTER_API_KEY="your_openrouter_key"
export HOME_ASSISTANT_TOKEN="your_ha_token"
export HOME_ASSISTANT_URL="your_ha_url"
```

### Running Individual Test Suites
```bash
# Core service tests
bundle exec rspec spec/services/performance_mode_service_spec.rb

# Background job tests
bundle exec rspec spec/jobs/performance_mode_job_spec.rb

# API endpoint tests
bundle exec rspec spec/requests/performance_mode_spec.rb

# Integration tests
bundle exec rspec spec/integration/performance_mode_*_spec.rb
```

### Running All Performance Mode Tests
```bash
bundle exec rspec spec/services/performance_mode_service_spec.rb \
                  spec/jobs/performance_mode_job_spec.rb \
                  spec/requests/performance_mode_spec.rb \
                  spec/services/cube_performance_spec.rb \
                  spec/integration/performance_mode_*_spec.rb
```

## VCR Cassette Management

### Recording New Cassettes
1. Delete existing cassette: `rm spec/cassettes/performance_mode/specific_test.yml`
2. Run test with real API: `VCR_RECORD_MODE=new_episodes bundle exec rspec spec/path/to/test.rb`
3. Commit updated cassette to repository

### Re-recording All Cassettes
```bash
# Remove all performance mode cassettes
rm -rf spec/cassettes/performance_mode/
rm -rf spec/cassettes/performance_mode_job/
rm -rf spec/cassettes/performance_mode_api/
rm -rf spec/cassettes/cube_performance/
rm -rf spec/cassettes/performance_llm/
rm -rf spec/cassettes/performance_state/
rm -rf spec/cassettes/performance_e2e/

# Re-record with real APIs
VCR_RECORD_MODE=new_episodes bundle exec rspec spec/services/performance_mode_service_spec.rb
# Repeat for other test files...
```

### Cassette Hygiene
- **Filter sensitive data**: VCR automatically filters API keys and tokens
- **Review before commit**: Check cassettes don't contain sensitive information
- **Keep cassettes minimal**: Only record necessary interactions
- **Update periodically**: Re-record when APIs change significantly

## Test Data and Mocking Strategy

### External Service Mocking
- **LLM calls**: Mocked responses with realistic content and timing
- **Home Assistant**: Mocked TTS broadcast calls
- **Background jobs**: Controlled execution with `perform_enqueued_jobs`
- **Cache operations**: Real Redis/memory cache with cleanup

### Timing Control
- **Speed-up factor**: Tests use `sleep(duration * 0.01)` for 100x speed-up
- **Realistic proportions**: Maintains relative timing between segments
- **Freeze time**: Uses `freeze_time` for deterministic timing tests
- **Travel time**: Uses `travel_to` for duration-based testing

### Data Consistency
- **Session cleanup**: Before/after hooks ensure clean state
- **Cache clearing**: Prevents test pollution
- **Job clearing**: Ensures no background job interference
- **Log cleanup**: Removes conversation logs between tests

## Test Coverage Goals

### Functional Coverage
- ✅ All API endpoints (start, stop, status, interrupt)
- ✅ All performance types (comedy, storytelling, improv, poetry, custom)
- ✅ All error scenarios (LLM failures, HA failures, cache failures)
- ✅ All state transitions (start → running → stop/interrupt)
- ✅ Concurrent session management
- ✅ Background job processing

### Integration Coverage
- ✅ Service → Job → LLM → HA workflow
- ✅ API → Service → Cache persistence
- ✅ Error propagation and recovery
- ✅ State consistency across components
- ✅ Performance timing and duration management
- ✅ Session isolation and cleanup

### Edge Case Coverage
- ✅ Very short/long durations
- ✅ Unicode session IDs
- ✅ Empty/malformed responses
- ✅ Service unavailability
- ✅ Cache corruption/unavailability
- ✅ Memory leak prevention

## Maintenance and Updates

### When to Update Tests
- **API changes**: LLM service or Home Assistant API modifications
- **Feature additions**: New performance types or capabilities
- **Error handling**: New failure modes or recovery mechanisms
- **Performance improvements**: Timing or resource optimization changes

### Test Debugging
- **VCR replay issues**: Check cassette format and API compatibility
- **Timing issues**: Adjust speed-up factors or use more `freeze_time`
- **State pollution**: Ensure proper cleanup in before/after hooks
- **Job execution**: Verify `perform_enqueued_jobs` vs `have_enqueued_job`

### Performance Optimization
- **Selective testing**: Use `focus: true` for specific test development
- **Cassette sharing**: Reuse cassettes where possible
- **Mock granularity**: Balance realism with test speed
- **Parallel execution**: Consider test parallelization for large suite

This comprehensive test suite provides confidence in the Performance Mode system's reliability, error handling, and integration points while maintaining fast execution through VCR cassettes and controlled mocking.