#!/usr/bin/env ruby
# Enhanced Model Test Harness
# Advanced version with detailed LLM call tracking and metrics
# Run with: ruby scripts/enhanced_model_test_harness.rb

require_relative '../config/environment'
require 'benchmark'
require 'json'

class EnhancedModelTestHarness
  def initialize
    @results = []
    @start_time = Time.current
    @llm_calls = []
    ensure_logs_directory
    
    # Find next sequential run number
    @run_number = find_next_run_number("enhanced_test_run")
    @log_file = File.open("logs/model_tests/enhanced_test_run_#{@run_number}.log", 'w')
    @log_file.sync = true
    
    # Hook into LLM service to track detailed metrics
    setup_llm_tracking
  end

  # Configuration - Edit these for your tests
  TEST_PROMPTS = [
    {
      type: :single,
      prompt: "Turn on the living room lights and tell me the current temperature",
      description: "Action + Query test"
    },
    {
      type: :single,
      prompt: "What's the weather like? Also change the music to something chill",
      description: "Query + Action test"
    },
    {
      type: :single,
      prompt: "Hello! How are you doing today?",
      description: "Pure conversation test"
    },
    {
      type: :single,
      prompt: "Set all lights to 50% brightness and play jazz music",
      description: "Multiple actions test"
    },
    {
      type: :multi,
      prompts: [
        "Turn on the lights in the kitchen",
        "Now also turn on the bedroom lights", 
        "Thanks, that's perfect!"
      ],
      description: "Multi-turn with context"
    }
  ].freeze

  NARRATIVE_MODELS = [
    "openai/gpt-4o",
    "anthropic/claude-3-5-sonnet",
    "openai/gpt-4o-mini"
  ].freeze

  TOOL_MODELS = [
    "openai/gpt-4o-mini",
    "anthropic/claude-3-haiku",
    "openai/gpt-4o"
  ].freeze

  # Test configurations
  TWO_TIER_MODE = true
  TEST_SESSION_ID = "enhanced_test_#{Time.current.to_i}"

  def run_tests
    log_header
    
    total_tests = calculate_total_tests
    current_test = 0
    
    log_section("Starting #{total_tests} total tests")
    
    NARRATIVE_MODELS.each do |narrative_model|
      if TWO_TIER_MODE
        TOOL_MODELS.each do |tool_model|
          TEST_PROMPTS.each do |test_config|
            current_test += 1
            run_single_test(test_config, narrative_model, tool_model, current_test, total_tests)
          end
        end
      else
        TEST_PROMPTS.each do |test_config|
          current_test += 1
          run_single_test(test_config, narrative_model, nil, current_test, total_tests)
        end
      end
    end
    
    log_summary
    log_detailed_metrics
    @log_file.close
  end

  private

  def setup_llm_tracking
    # Create a module to prepend to LlmService
    tracker = Module.new do
      def call_with_tools(messages:, tools: [], model: nil, **options)
        test_harness = Thread.current[:test_harness]
        call_id = SecureRandom.hex(8)
        
        start_time = Time.current
        
        if test_harness
          test_harness.track_llm_call_start(call_id, {
            type: :tool_call,
            model: model,
            messages: messages,
            tools: tools.map(&:name),
            tool_count: tools.size
          })
        end
        
        result = super
        
        end_time = Time.current
        
        if test_harness
          test_harness.track_llm_call_end(call_id, {
            response_time: end_time - start_time,
            content: result.content,
            tool_calls: result.tool_calls&.map(&:name) || [],
            usage: result.usage,
            model_used: result.model
          })
        end
        
        result
      end
      
      def call_with_structured_output(messages:, response_format:, model: nil, **options)
        test_harness = Thread.current[:test_harness]
        call_id = SecureRandom.hex(8)
        
        start_time = Time.current
        
        if test_harness
          test_harness.track_llm_call_start(call_id, {
            type: :structured_output,
            model: model,
            messages: messages,
            response_format: response_format.name
          })
        end
        
        result = super
        
        end_time = Time.current
        
        if test_harness
          test_harness.track_llm_call_end(call_id, {
            response_time: end_time - start_time,
            content: result.content,
            structured_output: result.structured_output,
            usage: result.usage,
            model_used: result.model
          })
        end
        
        result
      end
    end
    
    LlmService.singleton_class.prepend(tracker)
  end

  def track_llm_call_start(call_id, data)
    @llm_calls << {
      id: call_id,
      start_time: Time.current,
      start_data: data,
      end_data: nil
    }
  end

  def track_llm_call_end(call_id, data)
    call = @llm_calls.find { |c| c[:id] == call_id }
    if call
      call[:end_time] = Time.current
      call[:end_data] = data
    end
  end

  def calculate_total_tests
    if TWO_TIER_MODE
      NARRATIVE_MODELS.size * TOOL_MODELS.size * TEST_PROMPTS.size
    else
      NARRATIVE_MODELS.size * TEST_PROMPTS.size
    end
  end

  def run_single_test(test_config, narrative_model, tool_model, current_test, total_tests)
    log_test_header(test_config, narrative_model, tool_model, current_test, total_tests)
    
    # Set thread-local reference for LLM tracking
    Thread.current[:test_harness] = self
    
    # Clear LLM call tracking for this test
    test_start_calls = @llm_calls.size
    
    if test_config[:type] == :single
      result = test_single_conversation(test_config, narrative_model, tool_model)
    elsif test_config[:type] == :multi
      result = test_multi_turn(test_config, narrative_model, tool_model)
    end
    
    # Capture LLM calls for this test
    test_llm_calls = @llm_calls[test_start_calls..-1] || []
    result[:llm_calls] = test_llm_calls
    
    @results << result
    log_test_result(result)
    
  rescue => e
    error_result = {
      test_type: test_config[:type],
      test_description: test_config[:description],
      narrative_model: narrative_model,
      tool_model: tool_model,
      error: e.message,
      backtrace: e.backtrace.first(10),
      success: false,
      llm_calls: @llm_calls[test_start_calls..-1] || []
    }
    @results << error_result
    log_error(error_result)
  ensure
    Thread.current[:test_harness] = nil
  end

  def test_single_conversation(test_config, narrative_model, tool_model)
    log_line "Testing: #{test_config[:description]}"
    log_line "  Prompt: #{test_config[:prompt]}"
    log_line "  Narrative Model: #{narrative_model}"
    log_line "  Tool Model: #{tool_model || 'same as narrative'}"
    
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
      
      orchestrator = ConversationOrchestrator.new(
        session_id: session_id,
        message: test_config[:prompt],
        context: context
      )
      
      response = nil
      response_time = Benchmark.realtime do
        response = orchestrator.call
      end
      
      parsed = parse_response(response)
      
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
        response: response,
        parsed: parsed,
        timing: {
          total_response_time: response_time,
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
    log_line "Testing: #{test_config[:description]}"
    log_line "  Turns: #{test_config[:prompts].size}"
    log_line "  Narrative Model: #{narrative_model}"
    log_line "  Tool Model: #{tool_model || 'same as narrative'}"
    
    session_id = "#{TEST_SESSION_ID}_multi_#{SecureRandom.hex(4)}"
    turns = []
    total_time = 0
    
    if TWO_TIER_MODE && tool_model
      original_tool_model = Rails.configuration.try(:tool_calling_model)
      Rails.configuration.tool_calling_model = tool_model
      Rails.configuration.two_tier_tools_enabled = true
    else
      Rails.configuration.two_tier_tools_enabled = false
    end
    
    begin
      test_config[:prompts].each_with_index do |prompt, index|
        log_line "  Turn #{index + 1}: #{prompt}"
        
        turn_start = Time.current
        
        context = {
          model: narrative_model,
          session_id: session_id
        }
        
        orchestrator = ConversationOrchestrator.new(
          session_id: session_id,
          message: prompt,
          context: context
        )
        
        response = nil
        response_time = Benchmark.realtime do
          response = orchestrator.call
        end
        
        total_time += response_time
        parsed = parse_response(response)
        
        turns << {
          turn: index + 1,
          prompt: prompt,
          response: response,
          parsed: parsed,
          response_time: response_time,
          timestamp: turn_start
        }
        
        log_line "    Response (#{response_time.round(2)}s): #{parsed[:speech_text]}"
        
        # Brief pause between turns to simulate real conversation
        sleep(0.1)
      end
      
      if TWO_TIER_MODE && tool_model && defined?(original_tool_model)
        Rails.configuration.tool_calling_model = original_tool_model
      end
      
      {
        test_type: :multi,
        test_description: test_config[:description],
        turns: turns.size,
        narrative_model: narrative_model,
        tool_model: tool_model,
        session_id: session_id,
        turns_data: turns,
        timing: {
          total_conversation_time: total_time,
          average_turn_time: total_time / turns.size
        },
        success: true
      }
      
    rescue => e
      if TWO_TIER_MODE && tool_model && defined?(original_tool_model)
        Rails.configuration.tool_calling_model = original_tool_model
      end
      raise e
    end
  end

  def parse_response(response)
    # The actual speech text is deeply nested in the Home Assistant response format
    speech_text = response.dig(:response, :speech, :plain, :speech) ||
                  response.dig("response", "speech", "plain", "speech") ||
                  response.dig(:response_text) || 
                  response.dig(:text) || 
                  response.dig(:speech_text) ||
                  "No speech text found"
    
    # Extract other useful information
    targets = response.dig(:response, :data, :targets) ||
              response.dig("response", "data", "targets") ||
              response.dig(:targets) ||
              []
              
    success_entities = response.dig(:response, :data, :success) ||
                       response.dig("response", "data", "success") ||
                       response.dig(:success_entities) ||
                       []
    
    {
      speech_text: speech_text,
      continue_conversation: response.dig(:continue_conversation),
      end_conversation: response.dig(:end_conversation),
      success_entities: success_entities,
      targets: targets,
      conversation_id: response.dig(:conversation_id),
      raw_response: response
    }
  end

  def log_test_result(result)
    if result[:success]
      log_line "\nRESULT SUCCESS:"
      
      if result[:test_type] == :single
        log_line "  Speech: #{result[:parsed][:speech_text]}"
        log_line "  Continue: #{result[:parsed][:continue_conversation]}"
        log_line "  Entities: #{result[:parsed][:success_entities]&.size || 0}"
        log_line "  Targets: #{result[:parsed][:targets]&.size || 0}"
        log_line "  Total Time: #{result[:timing][:total_response_time].round(3)}s"
      else
        log_line "  Turns: #{result[:turns]}"
        log_line "  Total time: #{result[:timing][:total_conversation_time].round(3)}s"
        log_line "  Avg turn: #{result[:timing][:average_turn_time].round(3)}s"
      end
      
      # Log LLM call details
      if result[:llm_calls]&.any?
        log_line "  LLM CALLS:"
        result[:llm_calls].each_with_index do |call, i|
          log_llm_call(call, i + 1)
        end
      end
    end
  end

  def log_llm_call(call, index)
    return unless call[:start_data] && call[:end_data]
    
    log_line "    Call #{index}: #{call[:start_data][:type]}"
    log_line "      Model: #{call[:end_data][:model_used] || call[:start_data][:model]}"
    log_line "      Time: #{call[:end_data][:response_time].round(3)}s"
    
    if call[:start_data][:type] == :tool_call
      log_line "      Tools available: #{call[:start_data][:tool_count]}"
      log_line "      Tools called: #{call[:end_data][:tool_calls]&.join(', ') || 'none'}"
    elsif call[:start_data][:type] == :structured_output
      log_line "      Format: #{call[:start_data][:response_format]}"
      log_line "      Structured output: #{call[:end_data][:structured_output].present?}"
    end
    
    if call[:end_data][:usage]
      usage = call[:end_data][:usage]
      log_line "      Tokens: #{usage[:prompt_tokens] || usage['prompt_tokens'] || 'N/A'} prompt, #{usage[:completion_tokens] || usage['completion_tokens'] || 'N/A'} completion"
    end
    
    log_line "      Content: #{call[:end_data][:content] || 'N/A'}"
  end

  def log_detailed_metrics
    log_section("DETAILED METRICS")
    
    successful_tests = @results.select { |r| r[:success] }
    failed_tests = @results.select { |r| !r[:success] }
    
    # LLM performance by model
    log_line "LLM CALL PERFORMANCE:"
    all_llm_calls = successful_tests.flat_map { |r| r[:llm_calls] || [] }
    
    by_model = all_llm_calls.group_by { |call| call[:end_data]&.dig(:model_used) }
    by_model.each do |model, calls|
      next unless model
      
      times = calls.map { |c| c[:end_data][:response_time] }.compact
      avg_time = times.sum / times.size if times.any?
      
      tokens = calls.map { |c| 
        usage = c[:end_data][:usage]
        (usage[:prompt_tokens] || usage['prompt_tokens'] || 0) + 
        (usage[:completion_tokens] || usage['completion_tokens'] || 0)
      }.compact
      avg_tokens = tokens.sum / tokens.size if tokens.any?
      
      log_line "  #{model}: #{times.size} calls, #{avg_time&.round(3)}s avg, #{avg_tokens&.round(0)} tokens avg"
    end
    
    # Test type performance
    log_line "\nTEST TYPE PERFORMANCE:"
    single_tests = successful_tests.select { |r| r[:test_type] == :single }
    multi_tests = successful_tests.select { |r| r[:test_type] == :multi }
    
    if single_tests.any?
      avg_time = single_tests.sum { |r| r[:timing][:total_response_time] } / single_tests.size
      log_line "  Single conversations: #{single_tests.size} tests, #{avg_time.round(3)}s avg"
    end
    
    if multi_tests.any?
      avg_time = multi_tests.sum { |r| r[:timing][:total_conversation_time] } / multi_tests.size
      avg_turn_time = multi_tests.sum { |r| r[:timing][:average_turn_time] } / multi_tests.size
      log_line "  Multi-turn conversations: #{multi_tests.size} tests, #{avg_time.round(3)}s avg total, #{avg_turn_time.round(3)}s avg per turn"
    end
    
    # Model combination analysis
    if TWO_TIER_MODE
      log_line "\nMODEL COMBINATION ANALYSIS:"
      combination_performance = successful_tests.group_by { |r| [r[:narrative_model], r[:tool_model]] }
      
      combination_performance.each do |(narrative, tool), tests|
        single_tests_for_combo = tests.select { |t| t[:test_type] == :single }
        next unless single_tests_for_combo.any?
        
        avg_time = single_tests_for_combo.sum { |t| t[:timing][:total_response_time] } / single_tests_for_combo.size
        
        # Calculate LLM call breakdown
        all_calls = single_tests_for_combo.flat_map { |t| t[:llm_calls] || [] }
        narrative_calls = all_calls.select { |c| c[:start_data][:type] == :structured_output }
        tool_calls = all_calls.select { |c| c[:start_data][:type] == :tool_call }
        
        log_line "  #{narrative} + #{tool}:"
        log_line "    #{single_tests_for_combo.size} tests, #{avg_time.round(3)}s avg"
        log_line "    Narrative calls: #{narrative_calls.size} (#{(narrative_calls.sum { |c| c[:end_data][:response_time] } / narrative_calls.size).round(3)}s avg)" if narrative_calls.any?
        log_line "    Tool calls: #{tool_calls.size} (#{(tool_calls.sum { |c| c[:end_data][:response_time] } / tool_calls.size).round(3)}s avg)" if tool_calls.any?
      end
    end
    
    # Error analysis
    if failed_tests.any?
      log_line "\nERROR ANALYSIS:"
      error_counts = failed_tests.group_by { |t| t[:error] }
      error_counts.each do |error, tests|
        log_line "  #{error}: #{tests.size} occurrences"
      end
    end
  end

  def log_header
    log_line "=" * 80
    log_line "ENHANCED MODEL TEST HARNESS"
    log_line "Started: #{@start_time}"
    log_line "Two-tier mode: #{TWO_TIER_MODE}"
    log_line "Narrative models: #{NARRATIVE_MODELS.join(', ')}"
    log_line "Tool models: #{TOOL_MODELS.join(', ')}" if TWO_TIER_MODE
    log_line "Test scenarios: #{TEST_PROMPTS.size}"
    log_line "=" * 80
  end

  def log_test_header(test_config, narrative_model, tool_model, current_test, total_tests)
    log_line "\n" + "-" * 60
    log_line "TEST #{current_test}/#{total_tests}: #{test_config[:description]}"
    log_line "Type: #{test_config[:type].upcase}"
    log_line "Narrative: #{narrative_model}"
    log_line "Tool: #{tool_model || 'same as narrative'}"
    log_line "-" * 60
  end

  def log_error(error_result)
    log_line "\nERROR:"
    log_line "  Test: #{error_result[:test_description]}"
    log_line "  Message: #{error_result[:error]}"
    log_line "  Backtrace:"
    error_result[:backtrace]&.first(5)&.each do |line|
      log_line "    #{line}"
    end
  end

  def log_summary
    log_line "\n" + "=" * 80
    log_line "TEST SUMMARY"
    log_line "=" * 80
    log_line "Total tests: #{@results.size}"
    log_line "Successful: #{@results.count { |r| r[:success] }}"
    log_line "Failed: #{@results.count { |r| !r[:success] }}"
    
    elapsed = Time.current - @start_time
    log_line "Total execution time: #{elapsed.round(2)}s"
    log_line "Log saved to: logs/model_tests/enhanced_test_run_#{@run_number}.log"
  end

  def log_section(message)
    log_line "\n#{message}"
    log_line "-" * message.length
  end

  def log_line(message)
    puts message
    @log_file.puts message
  end

  def find_next_run_number(prefix = "test_run")
    # Look for existing files with sequential numbering (ignore timestamp-based files)
    existing_files = Dir.glob("logs/model_tests/#{prefix}_*.log")
    if existing_files.empty?
      1
    else
      numbers = existing_files.map do |file|
        match = file.match(/#{prefix}_(\d+)\.log/)
        if match
          number = match[1].to_i
          # Only count files with reasonable sequential numbers (1-9999), ignore timestamps
          number <= 9999 ? number : 0
        else
          0
        end
      end.select { |n| n > 0 }
      
      numbers.empty? ? 1 : numbers.max + 1
    end
  end

  def ensure_logs_directory
    Dir.mkdir('logs') unless Dir.exist?('logs')
    Dir.mkdir('logs/model_tests') unless Dir.exist?('logs/model_tests')
  end
end

# Run the tests if this script is executed directly
if __FILE__ == $0
  harness = EnhancedModelTestHarness.new
  harness.run_tests
end