# Model Test Harness

A comprehensive testing suite for benchmarking different AI model combinations in the GlitchCube conversational AI system.

## Quick Start

```bash
# Run basic test harness
ruby scripts/model_test_harness.rb

# Run enhanced version with detailed LLM tracking
ruby scripts/enhanced_model_test_harness.rb
```

## What It Tests

### Model Combinations
- **Two-tier mode**: Tests different narrative + tool-calling model combinations
- **Legacy mode**: Tests single models handling both narrative and tools

### Conversation Types
- **Single conversations**: One prompt, one response
- **Multi-turn conversations**: Context-aware conversation sequences

### Metrics Collected
- Response timing (total time, first token estimation)
- LLM call breakdown (narrative vs tool calling)
- Token usage per model
- Tool execution patterns
- Success/failure rates
- Model-specific performance

## Configuration

### Basic Configuration
Edit the constants at the top of the test files:

```ruby
NARRATIVE_MODELS = [
  "openai/gpt-4o",
  "anthropic/claude-3-5-sonnet"
]

TOOL_MODELS = [
  "openai/gpt-4o-mini", 
  "anthropic/claude-3-haiku"
]

TWO_TIER_MODE = true  # Set false for legacy mode testing
```

### Test Scenarios
Add custom test scenarios in the `TEST_PROMPTS` array:

```ruby
{
  type: :single,
  prompt: "Your test prompt here",
  description: "Description of what this tests"
}

{
  type: :multi,
  prompts: [
    "First message",
    "Second message", 
    "Third message"
  ],
  description: "Multi-turn test description"
}
```

## Output Example

```
========================================
ENHANCED MODEL TEST HARNESS
Started: 2024-01-20 10:30:45
Two-tier mode: true
Narrative models: openai/gpt-4o, anthropic/claude-3-5-sonnet
Tool models: openai/gpt-4o-mini, anthropic/claude-3-haiku
========================================

------------------------------------------------------------
TEST 1/8: Action + Query test
Type: SINGLE
Narrative: openai/gpt-4o
Tool: openai/gpt-4o-mini
------------------------------------------------------------

Testing: Action + Query test
  Prompt: Turn on the living room lights and tell me the current temperature
  Narrative Model: openai/gpt-4o
  Tool Model: openai/gpt-4o-mini

RESULT SUCCESS:
  Speech: I'll turn on the living room lights and check the temperature for you.
  Continue: false
  Entities: 2
  Targets: 1
  Total Time: 1.847s
  LLM CALLS:
    Call 1: structured_output
      Model: openai/gpt-4o
      Time: 0.923s
      Format: NarrativeResponseSchema
      Structured output: true
      Tokens: 450 prompt, 120 completion
      Content: I'll help you with both of those tasks right away.
    Call 2: tool_call
      Model: openai/gpt-4o-mini
      Time: 0.721s
      Tools available: 15
      Tools called: lights_turn_on, weather_get_current
      Tokens: 380 prompt, 85 completion
      Content: 
```

## Log Files

Results are saved to `logs/model_tests/` with timestamps:
- `test_run_[timestamp].log` - Basic harness results
- `enhanced_test_run_[timestamp].log` - Detailed harness with LLM call tracking

## Advanced Usage

### Testing Specific Model Combinations

```ruby
# Test only specific combinations
NARRATIVE_MODELS = ["openai/gpt-4o"]
TOOL_MODELS = ["openai/gpt-4o-mini", "anthropic/claude-3-haiku"]
```

### Adding Custom Metrics

The enhanced harness tracks LLM calls automatically. To add custom metrics, modify the `track_llm_call_*` methods.

### Performance Benchmarking

For speed testing, use scenarios with known tool usage patterns:

```ruby
{
  type: :single,
  prompt: "Turn on all lights",  # Known to trigger lights_turn_on
  description: "Simple action benchmark"
}
```

## Key Features

### Basic Harness (`model_test_harness.rb`)
- ✅ Model combination testing
- ✅ Single and multi-turn conversations  
- ✅ Basic timing metrics
- ✅ Response parsing
- ✅ Error handling with backtraces
- ✅ Human-readable logs

### Enhanced Harness (`enhanced_model_test_harness.rb`)
- ✅ All basic features plus:
- ✅ **Detailed LLM call tracking** - hooks into LlmService
- ✅ **Separate narrative/tool timing** - tracks each LLM call independently  
- ✅ **Token usage per call** - detailed usage metrics
- ✅ **Model performance breakdown** - per-model averages
- ✅ **Tool calling analysis** - which tools were actually called
- ✅ **Combination analysis** - narrative + tool model performance

## Troubleshooting

### Common Issues

1. **Models not found**: Ensure model names match your OpenRouter configuration
2. **Tool calling errors**: Check that tools are properly registered
3. **Session conflicts**: Each test uses unique session IDs to prevent conflicts

### Debug Mode

Add verbose logging by modifying the log level:

```ruby
Rails.logger.level = Logger::DEBUG
```

### Testing Individual Components

```ruby
# Test just narrative models (no tools)
Rails.configuration.two_tier_tools_enabled = false

# Test specific personas
context = { persona: 'jax' }
```

## Architecture

The test harness works by:

1. **Configuring models** temporarily in Rails configuration
2. **Creating unique sessions** for each test to prevent interference  
3. **Calling ConversationOrchestrator** directly with test prompts
4. **Tracking timing** at multiple levels (total, LLM calls, tool execution)
5. **Parsing responses** to extract speech, tools, and metadata
6. **Aggregating metrics** across all test runs

This gives you a realistic performance picture since it uses the same code path as production conversations.