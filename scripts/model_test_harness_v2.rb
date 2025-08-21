#!/usr/bin/env ruby
# =============================================================================
# 🤖 MODEL TEST HARNESS - Configuration-First Design
# =============================================================================

require_relative '../config/environment'
require 'benchmark'
require 'json'
require 'stringio'

# =============================================================================
# CONFIGURATION SECTION - Edit these to customize your testing
# =============================================================================

# EASY MODEL SELECTION - Change this one line to switch testing modes
MODEL_SELECTION_MODE = :speed_focused  # Options: :speed_focused, :quality_focused, :budget_focused, :custom

# CUSTOM MODELS (when MODEL_SELECTION_MODE = :custom)
CUSTOM_NARRATIVE_MODELS = [
  "google/gemini-2.5-flash",
  "anthropic/claude-3.5-haiku",
  "openai/gpt-5-mini"
].freeze

CUSTOM_TOOL_MODELS = [
  "google/gemini-2.5-flash",
  "anthropic/claude-3.5-haiku",
  "z-ai/glm-4.5-air"
].freeze

# MODEL BLACKLISTS (models to avoid, separated by reason)
EXPENSIVE_MODELS = [
  "openai/o1-pro",           # $150/$600 per million tokens - EXTREMELY EXPENSIVE
  "openai/gpt-4",            # $30/$60 per million tokens
  "openai/gpt-4-0314",       # $30/$60 per million tokens
  "openai/o3-pro",           # $20/$80 per million tokens
  "anthropic/claude-opus-4.1", # $15/$75 per million tokens
  "anthropic/claude-opus-4", # $15/$75 per million tokens
  "anthropic/claude-3-opus", # $15/$75 per million tokens
  "openai/o1",               # $15/$60 per million tokens
  "openai/gpt-4-turbo"      # $10/$30 per million tokens
].freeze

UNRELIABLE_MODELS = [
  "perplexity/sonar-reasoning",      # Often slow, designed for search not tools
  "openai/gpt-4o-search-preview",   # Search-focused, not tool-focused
  "x-ai/grok-vision-beta"          # Beta model, often unreliable
].freeze

# PREFERRED MODEL POOLS (used by automatic selection modes)
SPEED_FOCUSED_MODELS = {
  narrative: [
    "google/gemini-2.5-flash",    # Fast and cheap
    "anthropic/claude-3.5-haiku", # Lightning fast
    "z-ai/glm-4.5-air"           # Very cheap and fast
  ].freeze,

  tool: [
    "google/gemini-2.5-flash",    # Reliable function calling
    "anthropic/claude-3.5-haiku", # Fast tool execution
    "z-ai/glm-4.5-air",          # Budget-friendly
    "openai/gpt-5-mini"           # Good tool support
  ].freeze
}.freeze

QUALITY_FOCUSED_MODELS = {
  narrative: [
    "anthropic/claude-3.5-sonnet", # Best reasoning
    "google/gemini-2.5-pro",       # High quality
    "openai/gpt-5"                 # Premium tier
  ].freeze,

  tool: [
    "anthropic/claude-3.5-sonnet", # Excellent function calling
    "openai/gpt-5",                # Premium tool support
    "google/gemini-2.5-pro",       # Reliable execution
    "mistralai/mistral-large-2411" # Good capabilities
  ].freeze
}.freeze

BUDGET_FOCUSED_MODELS = {
  narrative: [
    "google/gemini-2.5-flash",     # Great value
    "z-ai/glm-4.5-air",           # Very cheap
    "anthropic/claude-3.5-haiku"  # Good price/performance
  ].freeze,

  tool: [
    "z-ai/glm-4.5-air",           # Cheapest with function calling
    "google/gemini-2.5-flash",    # Good value
    "anthropic/claude-3.5-haiku"  # Fast and cheap
  ].freeze
}.freeze

# TEST CONFIGURATION
TWO_TIER_MODE = true
SHOW_RAW_RESPONSES = false
VERBOSE_MODE = false
DEBUG_MODEL_SELECTION = true  # Show exactly which models are selected
TEST_SESSION_ID = "test_harness_#{Time.current.to_i}"

# QUICK TOOL-FOCUSED TESTS
TOOL_FOCUSED_TESTS = [
  "Turn on the cube lights",
  "Set all lights to red",
  "Turn off the lights",
  "Set lights to blue at 50% brightness",
  "Turn on rainbow light effect",
  "Play some electronic music",
  "Display 'Hello World' on screen",
  "Turn on strobe effects",
  "Activate party mode",
  "Turn off all effects",
  "Show current time on display",
  "Play ambient music",
  "Set lights to green",
  "Turn on disco ball effect",
  "Activate chill mode",
  "Display weather information",
  "Set lights to purple pulse",
  "Turn on fog machine",
  "Play upbeat music",
  "Turn everything off",
  "Set red alert lighting",
  "Display 'BURNING MAN 2025'",
  "Turn on laser effects",
  "Play relaxing sounds",
  "Activate sunrise lighting"
].freeze

# =============================================================================
# END CONFIGURATION - Implementation below
# =============================================================================

# Performance Tracker for model selection and historical data
class ModelPerformanceTracker
  attr_reader :performance_data

  def initialize(json_file: 'model_performance_scores.json')
    @json_file = json_file
    @performance_data = load_performance_data
  end

  def track_test_result(narrative_model:, tool_model:, response_time:, success:, cost: nil, tokens: nil)
    key = "#{narrative_model}+#{tool_model}"

    @performance_data[key] ||= {
      'tests_run' => 0,
      'successes' => 0,
      'total_response_time' => 0.0,
      'total_cost' => 0.0,
      'total_tokens' => 0,
      'avg_response_time' => 0.0,
      'success_rate' => 0.0,
      'cost_per_success' => 0.0,
      'narrative_model' => narrative_model,
      'tool_model' => tool_model
    }

    data = @performance_data[key]
    data['tests_run'] += 1
    data['successes'] += 1 if success
    data['total_response_time'] += response_time
    data['total_cost'] += cost if cost
    data['total_tokens'] += tokens if tokens

    # Calculate running averages
    data['avg_response_time'] = data['total_response_time'] / data['tests_run']
    data['success_rate'] = data['successes'].to_f / data['tests_run']
    data['cost_per_success'] = data['successes'] > 0 ? data['total_cost'] / data['successes'] : 0.0

    save_performance_data
  end

  def get_best_models(optimize_for: :speed, min_tests: 3)
    eligible = @performance_data.select { |_, data| data['tests_run'] >= min_tests }

    case optimize_for
    when :speed
      eligible.sort_by { |_, data| data['avg_response_time'] }
    when :cost
      eligible.sort_by { |_, data| data['cost_per_success'] }
    when :success_rate
      eligible.sort_by { |_, data| -data['success_rate'] }
    when :value # success rate / cost
      eligible.sort_by { |_, data| data['cost_per_success'] > 0 ? -data['success_rate'] / data['cost_per_success'] : 0 }
    else
      eligible.sort_by { |_, data| data['avg_response_time'] }
    end.first(10)
  end

  def performance_summary
    return "No performance data available" if @performance_data.empty?

    total_tests = @performance_data.values.sum { |data| data['tests_run'] }
    avg_success_rate = @performance_data.values.sum { |data| data['success_rate'] } / @performance_data.size

    "Total tests: #{total_tests}, Models tested: #{@performance_data.size}, Avg success rate: #{(avg_success_rate * 100).round(1)}%"
  end

  private

  def load_performance_data
    return {} unless File.exist?(@json_file)
    JSON.parse(File.read(@json_file))
  rescue JSON::ParserError
    {}
  end

  def save_performance_data
    File.write(@json_file, JSON.pretty_generate(@performance_data))
  end
end

# Simple Model Selection - Configuration-Driven
class ModelSelector
  def self.get_models
    # All blacklisted models combined
    all_blacklisted = (EXPENSIVE_MODELS + UNRELIABLE_MODELS).freeze

    case MODEL_SELECTION_MODE
    when :speed_focused
      {
        narrative: filter_available_models(SPEED_FOCUSED_MODELS[:narrative], all_blacklisted),
        tool: filter_available_models(SPEED_FOCUSED_MODELS[:tool], all_blacklisted)
      }
    when :quality_focused
      {
        narrative: filter_available_models(QUALITY_FOCUSED_MODELS[:narrative], all_blacklisted),
        tool: filter_available_models(QUALITY_FOCUSED_MODELS[:tool], all_blacklisted)
      }
    when :budget_focused
      {
        narrative: filter_available_models(BUDGET_FOCUSED_MODELS[:narrative], all_blacklisted),
        tool: filter_available_models(BUDGET_FOCUSED_MODELS[:tool], all_blacklisted)
      }
    when :custom
      {
        narrative: filter_available_models(CUSTOM_NARRATIVE_MODELS, all_blacklisted),
        tool: filter_available_models(CUSTOM_TOOL_MODELS, all_blacklisted)
      }
    else
      # Fallback to speed focused
      {
        narrative: filter_available_models(SPEED_FOCUSED_MODELS[:narrative], all_blacklisted),
        tool: filter_available_models(SPEED_FOCUSED_MODELS[:tool], all_blacklisted)
      }
    end
  end

  # Try using OpenRouter gem if available, fall back to configuration
  def self.get_models_with_openrouter_fallback
    begin
      # Try OpenRouter dynamic selection first
      openrouter_models = attempt_openrouter_selection
      return openrouter_models if openrouter_models && openrouter_models[:narrative].any?
    rescue => e
      puts "⚠️ OpenRouter selection failed: #{e.message}" if DEBUG_MODEL_SELECTION
    end

    # Fall back to configuration-based selection
    puts "📋 Using configuration-based model selection" if DEBUG_MODEL_SELECTION
    get_models
  end

  private

  def self.filter_available_models(models, blacklisted)
    # Remove blacklisted models and ensure we have at least one model
    filtered = models.reject { |model| blacklisted.any? { |blacklisted_model| model.include?(blacklisted_model) } }
    filtered.empty? ? [ "google/gemini-2.5-flash" ] : filtered # Emergency fallback
  end

  def self.attempt_openrouter_selection
    return nil unless defined?(OpenRouter::ModelSelector)

    all_blacklisted = EXPENSIVE_MODELS + UNRELIABLE_MODELS

    case MODEL_SELECTION_MODE
    when :speed_focused
      narrative_models = OpenRouter::ModelSelector.new
                                                  .optimize_for(:performance)
                                                  .avoid_patterns(*all_blacklisted)
                                                  .choose_with_fallbacks(limit: 3)

      tool_models = OpenRouter::ModelSelector.new
                                             .require(:function_calling)
                                             .optimize_for(:performance)
                                             .avoid_patterns(*all_blacklisted)
                                             .choose_with_fallbacks(limit: 3)
    when :quality_focused
      narrative_models = OpenRouter::ModelSelector.new
                                                  .prefer_providers("anthropic", "openai")
                                                  .optimize_for(:quality)
                                                  .avoid_patterns(*all_blacklisted)
                                                  .choose_with_fallbacks(limit: 3)

      tool_models = OpenRouter::ModelSelector.new
                                             .require(:function_calling)
                                             .prefer_providers("anthropic", "openai")
                                             .avoid_patterns(*all_blacklisted)
                                             .choose_with_fallbacks(limit: 3)
    when :budget_focused
      narrative_models = OpenRouter::ModelSelector.new
                                                  .within_budget(max_cost: 0.01)
                                                  .optimize_for(:cost)
                                                  .avoid_patterns(*all_blacklisted)
                                                  .choose_with_fallbacks(limit: 3)

      tool_models = OpenRouter::ModelSelector.new
                                             .require(:function_calling)
                                             .within_budget(max_cost: 0.01)
                                             .avoid_patterns(*all_blacklisted)
                                             .choose_with_fallbacks(limit: 3)
    else
      return nil # Use configuration for custom mode
    end

    {
      narrative: narrative_models || [],
      tool: tool_models || []
    }
  rescue => e
    puts "OpenRouter selection error: #{e.message}" if DEBUG_MODEL_SELECTION
    nil
  end
end

class ModelTestHarness
  def initialize
    @results = []
    @start_time = Time.current
    @performance_tracker = ModelPerformanceTracker.new
    ensure_logs_directory

    # Find next sequential run number
    @run_number = find_next_run_number("test_run")
    @log_file = File.open("logs/model_tests/test_run_#{@run_number}.log", 'w')
    @log_file.sync = true

    puts "📊 #{@performance_tracker.performance_summary}"
  end

  # Test prompts
  TEST_PROMPTS = [
    {
      type: :single,
      prompt: "What's your name and where are you from CUBE?"
    },
    {
      type: :multi,
      prompts: [
        "Turn on all the lights to maximum brightness",
        "Play some chill electronic music for me",
        "Show 'Welcome to Burning Man!' on your display",
        "Turn on the strobe lights!",
        "Activate emergency mode",
        "Do whatever you want DO ALL THE THINGS!"
      ],
      description: "All tool domains test"
    },
    {
      type: :tool_performance,
      prompts: TOOL_FOCUSED_TESTS,
      description: "25 quick tool tests for performance benchmarking"
    }
  ].freeze

  def run_tests
    # Get models using new configuration-driven approach
    models = ModelSelector.get_models_with_openrouter_fallback
    narrative_models = models[:narrative]
    tool_models = models[:tool]

    print_header(narrative_models, tool_models)

    if DEBUG_MODEL_SELECTION
      puts "\n🔍 DEBUG: Model Selection Details:"
      puts "   Mode: #{MODEL_SELECTION_MODE}"
      puts "   Narrative Models: #{narrative_models.join(', ')}"
      puts "   Tool Models: #{tool_models.join(', ')}"
      puts "   Blacklisted Expensive: #{EXPENSIVE_MODELS.size} models"
      puts "   Blacklisted Unreliable: #{UNRELIABLE_MODELS.size} models"
    end

    total_tests = calculate_total_tests(narrative_models, tool_models)
    current_test = 0

    puts "\n🚀 Starting #{total_tests} total tests\n"

    if TWO_TIER_MODE
      # Run 1-1 pairs, looping back if arrays are different lengths
      max_models = [ narrative_models.size, tool_models.size ].max

      (0...max_models).each do |index|
        narrative_model = narrative_models[index % narrative_models.size]
        tool_model = tool_models[index % tool_models.size]

        TEST_PROMPTS.each do |test_config|
          current_test += 1
          run_single_test(test_config, narrative_model, tool_model, current_test, total_tests)
        end
      end
    else
      narrative_models.each do |narrative_model|
        TEST_PROMPTS.each do |test_config|
          current_test += 1
          run_single_test(test_config, narrative_model, nil, current_test, total_tests)
        end
      end
    end

    print_summary
    @log_file.close
  end

  def calculate_total_tests(narrative_models, tool_models)
    if TWO_TIER_MODE
      # Calculate based on 1-1 pairing, not full permutation
      max_models = [ narrative_models.size, tool_models.size ].max
      max_models * TEST_PROMPTS.size
    else
      narrative_models.size * TEST_PROMPTS.size
    end
  end

  private

  def run_single_test(test_config, narrative_model, tool_model, current_test, total_tests)
    print_test_header(test_config, narrative_model, tool_model, current_test, total_tests)

    if test_config[:type] == :single
      result = test_single_conversation(test_config, narrative_model, tool_model)
    elsif test_config[:type] == :multi
      result = test_multi_turn(test_config, narrative_model, tool_model)
    elsif test_config[:type] == :tool_performance
      result = test_tool_performance(test_config, narrative_model, tool_model)
    end

    # Track performance data
    if result && result[:success]
      response_time = result.dig(:timing, :total_response_time) || 0
      tokens = extract_token_count(result)
      cost = calculate_estimated_cost(result, tokens)

      @performance_tracker.track_test_result(
        narrative_model: narrative_model,
        tool_model: tool_model,
        response_time: response_time,
        success: true,
        cost: cost,
        tokens: tokens
      )
    end

    @results << result
    print_test_result(result)

  rescue => e
    # Track failed test
    @performance_tracker.track_test_result(
      narrative_model: narrative_model,
      tool_model: tool_model,
      response_time: 0,
      success: false
    )

    error_result = {
      test_type: test_config[:type],
      test_description: test_config[:description],
      narrative_model: narrative_model,
      tool_model: tool_model,
      error: e.message,
      backtrace: e.backtrace.first(5),
      success: false
    }
    @results << error_result
    print_error(error_result)
  end

  def test_single_conversation(test_config, narrative_model, tool_model)
    start_time = Time.current

    begin
      session_id = "#{TEST_SESSION_ID}_#{SecureRandom.hex(4)}"

      context = {
        model: narrative_model,
        session_id: session_id
      }

      # Configure models
      if TWO_TIER_MODE && tool_model
        original_tool_model = Rails.configuration.try(:tool_calling_model)
        Rails.configuration.tool_calling_model = tool_model
        Rails.configuration.two_tier_tools_enabled = true
      else
        Rails.configuration.two_tier_tools_enabled = false
      end

      # Capture detailed execution with timing
      detailed_execution = capture_detailed_execution do
        orchestrator = ConversationOrchestrator.new(
          session_id: session_id,
          message: test_config[:prompt],
          context: context
        )

        @response = nil
        @response_time = Benchmark.realtime do
          @response = orchestrator.call
        end
      end

      parsed = parse_response(@response)

      tool_activity = parse_tool_activity_from_logs(detailed_execution[:rails_logs])

      # Extract narrative metadata from structured output if available
      if tool_activity[:structured_output] && tool_activity[:structured_output][:parsing_success]
        structured = tool_activity[:structured_output]
        parsed[:inner_thoughts] = structured[:inner_thoughts]
        parsed[:current_mood] = structured[:current_mood]
        parsed[:pressing_questions] = structured[:pressing_questions]
        parsed[:continue_conversation] = structured[:continue_conversation]
      end

      # Restore configuration
      if TWO_TIER_MODE && tool_model && defined?(original_tool_model)
        Rails.configuration.tool_calling_model = original_tool_model
      end

      {
        test_type: :single,
        test_description: test_config[:description],
        prompt: test_config[:prompt],
        narrative_model: narrative_model,
        tool_model: tool_model,
        session_id: session_id,
        response: @response,
        parsed: parsed,
        tool_activity: tool_activity,
        detailed_execution: detailed_execution,
        timing: {
          total_response_time: @response_time,
          detailed_total_time: detailed_execution[:total_time],
          start_time: start_time,
          end_time: Time.current
        },
        success: true,
        timestamp: start_time
      }

    rescue => e
      if TWO_TIER_MODE && tool_model && defined?(original_tool_model)
        Rails.configuration.tool_calling_model = original_tool_model
      end
      raise e
    end
  end

  def test_multi_turn(test_config, narrative_model, tool_model)
    # Implementation similar to original but simplified for space
    # ... (abbreviated for clarity in this example)
  end

  def test_tool_performance(test_config, narrative_model, tool_model)
    # Implementation similar to original but simplified for space
    # ... (abbreviated for clarity in this example)
  end

  # Helper methods similar to original implementation
  def capture_detailed_execution
    # ... (implementation details)
  end

  def parse_tool_activity_from_logs(logs)
    # ... (implementation details)
  end

  def parse_response(response)
    # ... (implementation details)
  end

  def print_header(narrative_models, tool_models)
    puts "=" * 80
    puts "🤖 MODEL TEST HARNESS (Configuration-First Design)"
    puts "Started: #{@start_time.strftime('%H:%M:%S')}"
    puts "Mode: #{MODEL_SELECTION_MODE.to_s.upcase} (#{TWO_TIER_MODE ? 'Two-tier' : 'Legacy'})"
    puts "Narrative models: #{narrative_models.join(', ')}"
    puts "Tool models: #{tool_models.join(', ')}" if TWO_TIER_MODE
    puts "Test scenarios: #{TEST_PROMPTS.size}"
    puts "=" * 80

    # Also log to file
    log_to_file("MODEL TEST HARNESS - Started: #{@start_time}")
    log_to_file("Mode: #{MODEL_SELECTION_MODE} (#{TWO_TIER_MODE ? 'Two-tier' : 'Legacy'})")
    log_to_file("Narrative models: #{narrative_models.join(', ')}")
    log_to_file("Tool models: #{tool_models.join(', ')}") if TWO_TIER_MODE
  end

  # Additional helper methods from original implementation...
  def print_test_header(test_config, narrative_model, tool_model, current_test, total_tests)
    # ... (implementation)
  end

  def print_test_result(result)
    # ... (implementation)
  end

  def print_error(error_result)
    # ... (implementation)
  end

  def print_summary
    # ... (implementation)
  end

  def log_to_file(message)
    @log_file.puts message
  end

  def find_next_run_number(prefix = "test_run")
    # ... (implementation)
  end

  def ensure_logs_directory
    Dir.mkdir('logs') unless Dir.exist?('logs')
    Dir.mkdir('logs/model_tests') unless Dir.exist?('logs/model_tests')
  end

  def extract_token_count(result)
    # ... (implementation)
  end

  def calculate_estimated_cost(result, tokens)
    # ... (implementation)
  end
end

# Run the tests if this script is executed directly
if __FILE__ == $0
  harness = ModelTestHarness.new
  harness.run_tests
end
