#!/usr/bin/env ruby
# Demo Test Harness - Quick validation that the system works
# Run with: ruby scripts/demo_test_harness.rb

require_relative '../config/environment'
require 'benchmark'

puts "🧪 Demo Test Harness - Quick System Validation"
puts "=" * 50

# Simple test configuration
TEST_PROMPT = "Hello! How are you doing today?"
NARRATIVE_MODEL = "openai/gpt-4o-mini"  # Fast, cheap model for testing

puts "Testing basic conversation flow..."
puts "Prompt: #{TEST_PROMPT}"
puts "Model: #{NARRATIVE_MODEL}"
puts "-" * 30

begin
  # Create test session
  session_id = "demo_test_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
  
  # Configure for single model (legacy mode)
  Rails.configuration.two_tier_tools_enabled = false
  
  context = {
    model: NARRATIVE_MODEL,
    session_id: session_id
  }
  
  # Time the conversation
  start_time = Time.current
  
  orchestrator = ConversationOrchestrator.new(
    session_id: session_id,
    message: TEST_PROMPT,
    context: context
  )
  
  response_time = Benchmark.realtime do
    @response = orchestrator.call
  end
  
  end_time = Time.current
  
  # Display results
  puts "\n✅ SUCCESS!"
  puts "Response time: #{response_time.round(3)}s"
  puts "Response text: #{@response.dig(:response_text) || @response.dig(:text)}"
  puts "Continue conversation: #{@response.dig(:continue_conversation)}"
  puts "End conversation: #{@response.dig(:end_conversation)}"
  
  if @response.dig(:success_entities)&.any?
    puts "Success entities: #{@response[:success_entities].size}"
  end
  
  if @response.dig(:targets)&.any?
    puts "Targets: #{@response[:targets].size}"
  end
  
  puts "\n🎉 System is working! Your test harnesses should run successfully."
  puts "\nNext steps:"
  puts "1. Run: ruby scripts/model_test_harness.rb"
  puts "2. Or: ruby scripts/enhanced_model_test_harness.rb"
  puts "3. Check logs in: logs/model_tests/"

rescue => e
  puts "\n❌ ERROR: #{e.message}"
  puts "\nBacktrace:"
  e.backtrace.first(5).each do |line|
    puts "  #{line}"
  end
  puts "\nThe test harness may not work correctly. Check your configuration."
end