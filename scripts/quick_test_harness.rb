#!/usr/bin/env ruby
# Quick Test Harness - Fast model testing for development
# Run with: ruby scripts/quick_test_harness.rb

require_relative '../config/environment'
require 'benchmark'

class QuickTestHarness
  def initialize
    @results = []
    @start_time = Time.current
  end

  # Quick prompts for testing
  QUICK_TESTS = [
    "Turn on the lights",
    "Hello! How are you?",
    "Play some music and set mood lighting"
  ].freeze

  # Just a couple models to test quickly
  MODELS_TO_TEST = [
    { narrative: "openai/gpt-4o-mini", tool: "openai/gpt-4o-mini" },
    { narrative: "anthropic/claude-3.5-haiku", tool: "anthropic/claude-3.5-haiku" }
  ].freeze

  def run_tests
    puts "🚀 QUICK TEST HARNESS"
    puts "=" * 50
    puts "Tests: #{QUICK_TESTS.size}"
    puts "Models: #{MODELS_TO_TEST.size}"
    puts "Total: #{QUICK_TESTS.size * MODELS_TO_TEST.size} tests"
    puts "=" * 50

    test_count = 0
    total_tests = QUICK_TESTS.size * MODELS_TO_TEST.size

    MODELS_TO_TEST.each do |model_config|
      QUICK_TESTS.each do |prompt|
        test_count += 1
        puts "\n#{test_count}/#{total_tests}: Testing #{model_config[:narrative].split('/').last} with \"#{prompt.truncate(30)}\""

        result = run_single_test(prompt, model_config[:narrative], model_config[:tool])
        @results << result

        if result[:success]
          puts "✅ SUCCESS (#{result[:time].round(2)}s): #{result[:speech_text].truncate(60)}"
        else
          puts "❌ FAILED: #{result[:error]&.truncate(60)}"
        end
      end
    end

    print_summary
  end

  private

  def run_single_test(prompt, narrative_model, tool_model)
    start_time = Time.current

    begin
      session_id = "quick_test_#{SecureRandom.hex(4)}"

      # Configure two-tier mode
      original_tool_model = Rails.configuration.try(:tool_calling_model)
      Rails.configuration.tool_calling_model = tool_model
      Rails.configuration.two_tier_tools_enabled = true

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
      time_taken = Benchmark.realtime do
        response = orchestrator.call
      end

      # Restore config
      Rails.configuration.tool_calling_model = original_tool_model if original_tool_model

      # Extract speech text
      speech_text = response.dig(:response, :speech, :plain, :speech) ||
                    response.dig("response", "speech", "plain", "speech") ||
                    "No speech found"

      {
        success: true,
        time: time_taken,
        speech_text: speech_text,
        narrative_model: narrative_model,
        tool_model: tool_model,
        prompt: prompt,
        response: response
      }

    rescue => e
      Rails.configuration.tool_calling_model = original_tool_model if original_tool_model

      {
        success: false,
        time: Time.current - start_time,
        error: e.message,
        narrative_model: narrative_model,
        tool_model: tool_model,
        prompt: prompt
      }
    end
  end

  def print_summary
    puts "\n" + "=" * 50
    puts "📊 QUICK TEST SUMMARY"
    puts "=" * 50

    successful = @results.count { |r| r[:success] }
    failed = @results.count { |r| !r[:success] }

    puts "✅ Successful: #{successful}"
    puts "❌ Failed: #{failed}"
    puts "📈 Success Rate: #{((successful.to_f / @results.size) * 100).round(1)}%"

    if successful > 0
      successful_tests = @results.select { |r| r[:success] }
      avg_time = successful_tests.sum { |r| r[:time] } / successful_tests.size
      puts "⏱️  Average Time: #{avg_time.round(2)}s"

      fastest = successful_tests.min_by { |r| r[:time] }
      slowest = successful_tests.max_by { |r| r[:time] }

      puts "🥇 Fastest: #{fastest[:narrative_model].split('/').last} (#{fastest[:time].round(2)}s)"
      puts "🐢 Slowest: #{slowest[:narrative_model].split('/').last} (#{slowest[:time].round(2)}s)"
    end

    if failed > 0
      puts "\n💥 FAILURES:"
      @results.select { |r| !r[:success] }.each do |failure|
        puts "  #{failure[:narrative_model].split('/').last}: #{failure[:error]}"
      end
    end

    elapsed = Time.current - @start_time
    puts "\n⏱️  Total Time: #{elapsed.round(1)}s"
  end
end

# Run the tests if this script is executed directly
if __FILE__ == $0
  harness = QuickTestHarness.new
  harness.run_tests
end
