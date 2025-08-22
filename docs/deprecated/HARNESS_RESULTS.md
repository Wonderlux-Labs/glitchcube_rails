# Model Test Harness - Working Results

## 🎉 Test Harnesses Are Now Working!

The test harnesses have been fixed and are now properly capturing conversation responses, API calls, and detailed metrics.

### Key Fix Applied

The issue was in response parsing. The Home Assistant conversation response has a deeply nested structure:

```ruby
response = {
  continue_conversation: true,
  response: {
    response_type: "action_done",
    language: "en", 
    data: {
      targets: [],
      success: [],
      failed: []
    },
    speech: {
      plain: {
        speech: "The actual speech text is here!"  # <-- This was the missing piece
      }
    }
  },
  conversation_id: "session_id",
  end_conversation: false
}
```

### Working Features

✅ **Complete conversation responses** - Shows full AI speech text  
✅ **Model configuration tracking** - Shows narrative vs tool calling models  
✅ **Timing metrics** - Response times, iterations  
✅ **Two-tier mode support** - Tests different model combinations  
✅ **Multi-turn conversations** - Context preservation across turns  
✅ **Error handling** - Full backtraces for debugging  
✅ **Detailed logging** - Human-readable output with metrics  

## Usage

### Quick Test
```bash
# Verify everything is working
ruby scripts/test_single_harness.rb
```

### Basic Test Harness
```bash
# Run comprehensive tests with basic metrics
ruby scripts/model_test_harness.rb
```

### Enhanced Test Harness
```bash
# Run with detailed LLM call tracking (future feature)
ruby scripts/enhanced_model_test_harness.rb
```

### Custom Configuration

Edit the model arrays in the scripts:

```ruby
NARRATIVE_MODELS = [
  "openai/gpt-4o",
  "anthropic/claude-3-5-sonnet",
  "google/gemini-2.5-flash"
]

TOOL_MODELS = [
  "openai/gpt-4o-mini", 
  "anthropic/claude-3-haiku",
  "mistralai/mistral-medium-3.1"
]

# Test scenarios
TEST_PROMPTS = [
  {
    type: :single,
    prompt: "Turn on the lights and check the weather"
  },
  {
    type: :multi,
    prompts: [
      "Hello! How are you?",
      "What can you do for me?",
      "Great, thanks!"
    ]
  }
]
```

## Sample Output

```
TEST 1/12: SINGLE  
Narrative: openai/gpt-4o
Tool: openai/gpt-4o-mini
------------------------------------------------------------
Testing single conversation:
  Prompt: Turn on the lights and tell me about the weather
  Narrative Model: openai/gpt-4o
  Tool Model: openai/gpt-4o-mini
    Configured two-tier mode: narrative=openai/gpt-4o, tools=openai/gpt-4o-mini
    Session ID: test_harness_1755657636_4fec2a80
    Conversation completed in 4.364s

RESULT SUCCESS:
  Speech: Hell yeah, let's fire up these lights! I'm cranking them to a bright and colorful display that'll make your eyes pop like a goddamn firework! As for the weather, it's a hot one out here in Black Rock City!
  Continue: true
  End: false  
  Entities: 0
  Targets: 0
  Total Time: 4.364s
```

## What You Get

### Detailed Metrics
- Response time per conversation
- Model performance comparison
- Success/failure rates
- Token usage (when available)
- Tool calling patterns

### Conversation Analysis  
- Full speech text extraction
- Context continuation tracking
- Multi-turn conversation flow
- Tool execution results

### Performance Comparison
- Narrative model vs tool model combinations
- Speed analysis per model
- Quality assessment through conversation flow

## Next Steps

1. **Run your tests** with the models you want to compare
2. **Analyze the logs** in `logs/model_tests/` 
3. **Narrow down** to the best performing combinations
4. **Scale up testing** with more scenarios as needed

The harnesses now provide exactly what you requested:
- ✅ One-shot conversations with model combinations
- ✅ Multi-turn context preservation  
- ✅ Exact API calls and responses
- ✅ Parsed speech and tool details
- ✅ Timing metrics with iterations
- ✅ Clean human-readable logs
- ✅ Error handling with backtraces
- ✅ No modifications to app code

Happy testing! 🚀