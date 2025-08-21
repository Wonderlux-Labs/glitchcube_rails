#!/usr/bin/env ruby
# Quick test of the model test harness with minimal configuration
require_relative '../config/environment'

# Simple configuration for testing
class QuickModelTestHarness
  def initialize
    @start_time = Time.current
    ensure_logs_directory
    @log_file = File.open("logs/model_tests/quick_test_#{@start_time.to_i}.log", 'w')
    @log_file.sync = true
  end

  # Minimal configuration
  TEST_PROMPTS = [
    {
      type: :single,
      prompt: "Turn on the lights and tell me about the weather"
    }
  ].freeze

  NARRATIVE_MODELS = [ "openai/gpt-4o-mini" ].freeze
  TOOL_MODELS = [ "openai/gpt-4o-mini" ].freeze
  TWO_TIER_MODE = true
  TEST_SESSION_ID = "quick_test_#{Time.current.to_i}"

  def run_tests
    log_header

    NARRATIVE_MODELS.each do |narrative_model|
      TOOL_MODELS.each do |tool_model|
        TEST_PROMPTS.each_with_index do |test_config, index|
          run_single_test(test_config, narrative_model, tool_model, index + 1, 1)
        end
      end
    end

    @log_file.close
  end

  private

  def run_single_test(test_config, narrative_model, tool_model, current_test, total_tests)
    log_test_header(test_config, narrative_model, tool_model, current_test, total_tests)

    result = test_single_conversation(test_config[:prompt], narrative_model, tool_model)
    log_test_result(result)

  rescue => e
    log_line "ERROR: #{e.message}"
    e.backtrace.first(3).each { |line| log_line "  #{line}" }
  end

  def test_single_conversation(prompt, narrative_model, tool_model)
    log_line "Testing single conversation:"
    log_line "  Prompt: #{prompt}"
    log_line "  Narrative Model: #{narrative_model}"
    log_line "  Tool Model: #{tool_model || 'same as narrative'}"

    start_time = Time.current

    # Create a unique session for this test
    session_id = "#{TEST_SESSION_ID}_#{SecureRandom.hex(4)}"

    context = {
      model: narrative_model,
      session_id: session_id
    }

    # Temporarily override tool calling model if in two-tier mode
    if TWO_TIER_MODE && tool_model
      original_tool_model = Rails.configuration.try(:tool_calling_model)
      Rails.configuration.tool_calling_model = tool_model
      Rails.configuration.two_tier_tools_enabled = true
      log_line "    Configured two-tier mode: narrative=#{narrative_model}, tools=#{tool_model}"
    else
      Rails.configuration.two_tier_tools_enabled = false
      log_line "    Configured legacy mode: single model=#{narrative_model}"
    end

    log_line "    Session ID: #{session_id}"
    log_line "    Starting conversation orchestration..."

    # Execute the conversation
    orchestrator = ConversationOrchestrator.new(
      session_id: session_id,
      message: prompt,
      context: context
    )

    response = nil
    response_time = Benchmark.realtime do
      response = orchestrator.call
    end

    log_line "    Conversation completed in #{response_time.round(3)}s"

    # Parse the response
    parsed = parse_response(response)

    # Restore original configuration
    if TWO_TIER_MODE && tool_model && defined?(original_tool_model)
      Rails.configuration.tool_calling_model = original_tool_model
    end

    {
      test_type: :single,
      prompt: prompt,
      narrative_model: narrative_model,
      tool_model: tool_model,
      session_id: session_id,
      response: response,
      parsed: parsed,
      timing: {
        total_response_time: response_time
      },
      success: true,
      timestamp: start_time
    }
  end

  def parse_response(response)
    log_line "    RAW RESPONSE KEYS: #{response.keys.inspect}"

    # The actual speech text is deeply nested in the Home Assistant response format
    speech_text = response.dig(:response, :speech, :plain, :speech) ||
                  response.dig("response", "speech", "plain", "speech") ||
                  "No speech text found"

    targets = response.dig(:response, :data, :targets) || []
    success_entities = response.dig(:response, :data, :success) || []

    log_line "    Extracted speech text: #{speech_text.truncate(100)}"
    log_line "    Targets: #{targets.size}, Success entities: #{success_entities.size}"

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
      log_line "  Speech: #{result[:parsed][:speech_text]}"
      log_line "  Continue: #{result[:parsed][:continue_conversation]}"
      log_line "  End: #{result[:parsed][:end_conversation]}"
      log_line "  Entities: #{result[:parsed][:success_entities]&.size || 0}"
      log_line "  Targets: #{result[:parsed][:targets]&.size || 0}"
      log_line "  Total Time: #{result[:timing][:total_response_time].round(3)}s"
    end
  end

  def log_header
    log_line "=" * 80
    log_line "QUICK MODEL TEST HARNESS"
    log_line "Started: #{@start_time}"
    log_line "Two-tier mode: #{TWO_TIER_MODE}"
    log_line "=" * 80
  end

  def log_test_header(test_config, narrative_model, tool_model, current_test, total_tests)
    log_line "\n" + "-" * 60
    log_line "TEST #{current_test}/#{total_tests}: #{test_config[:type].upcase}"
    log_line "Narrative: #{narrative_model}"
    log_line "Tool: #{tool_model || 'same as narrative'}"
    log_line "-" * 60
  end

  def log_line(message)
    puts message
    @log_file.puts "#{Time.current.strftime('%H:%M:%S.%3N')} #{message}"
  end

  def ensure_logs_directory
    Dir.mkdir('logs') unless Dir.exist?('logs')
    Dir.mkdir('logs/model_tests') unless Dir.exist?('logs/model_tests')
  end
end

# Run the test
harness = QuickModelTestHarness.new
harness.run_tests
