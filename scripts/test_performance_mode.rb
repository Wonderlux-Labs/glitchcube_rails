#!/usr/bin/env ruby
# Test Performance Mode
# Run with: ruby scripts/test_performance_mode.rb

require_relative '../config/environment'

class PerformanceModeTest
  def initialize
    @session_id = "test_performance_#{Time.current.to_i}"
  end

  def run_tests
    puts "🎭 PERFORMANCE MODE TESTING"
    puts "=" * 50
    puts "Session ID: #{@session_id}"
    puts "=" * 50

    begin
      # Test 1: Start a comedy performance (short duration for testing)
      puts "\n🎪 Test 1: Starting 2-minute comedy performance..."
      CubePerformance.standup_comedy(
        duration_minutes: 2,
        session_id: @session_id
      )

      # Give it a moment to start
      sleep(2)

      # Test 2: Check status
      puts "\n📊 Test 2: Checking performance status..."
      status = CubePerformance.performance_status(@session_id)
      puts "Status: #{status}"

      # Test 3: Wait and check if segments are being generated
      puts "\n⏱️ Test 3: Waiting for first performance segment..."
      sleep(15) # Wait for first segment

      # Check logs to see if segments are generating
      puts "\n📋 Recent log entries:"
      show_recent_logs

      # Test 4: Interrupt performance
      puts "\n🛑 Test 4: Testing wake word interruption..."
      service = PerformanceModeService.get_active_performance(@session_id)
      if service&.is_running?
        service.interrupt_for_wake_word
        puts "✅ Performance interrupted successfully"
      else
        puts "❌ No active performance to interrupt"
      end

      # Test 5: Final status check
      puts "\n📊 Test 5: Final status check..."
      final_status = CubePerformance.performance_status(@session_id)
      puts "Final Status: #{final_status}"

    rescue => e
      puts "❌ Test failed: #{e.message}"
      puts e.backtrace.first(5)
    end

    puts "\n✅ Performance mode testing complete!"
  end

  private

  def show_recent_logs
    # Show recent Rails logs related to performance mode
    begin
      log_file = Rails.root.join('log', 'development.log')
      if File.exist?(log_file)
        recent_lines = `tail -20 #{log_file}`.split("\n")
        performance_lines = recent_lines.select { |line| line.include?("Performance") || line.include?("🎭") || line.include?("🎪") }

        if performance_lines.any?
          puts "Recent performance logs:"
          performance_lines.each { |line| puts "  #{line}" }
        else
          puts "No recent performance logs found"
        end
      else
        puts "Log file not found"
      end
    rescue => e
      puts "Could not read logs: #{e.message}"
    end
  end
end

# Quick API test
class PerformanceModeAPITest
  def self.run
    puts "\n🔗 PERFORMANCE MODE API TESTING"
    puts "=" * 50

    session_id = "api_test_#{Time.current.to_i}"

    # Test API endpoints using curl (if available)
    base_url = "http://localhost:3000/api/v1/performance_mode"

    puts "\n🚀 Testing API start endpoint..."
    start_command = <<~CMD
      curl -X POST "#{base_url}/start" \
        -H "Content-Type: application/json" \
        -H "X-Session-ID: #{session_id}" \
        -d '{
          "performance_type": "comedy",
          "duration_minutes": 1,
          "prompt": "Test comedy routine"
        }' -s
    CMD

    puts "Command: #{start_command.strip}"

    if system("which curl > /dev/null 2>&1")
      puts "\nAPI Response:"
      system(start_command)

      sleep(2)

      puts "\n\n📊 Testing status endpoint..."
      puts system("curl -X GET '#{base_url}/status' -H 'X-Session-ID: #{session_id}' -s")

      puts "\n\n🛑 Testing stop endpoint..."
      puts system("curl -X POST '#{base_url}/stop' -H 'X-Session-ID: #{session_id}' -s")
    else
      puts "❌ curl not available for API testing"
    end
  end
end

if __FILE__ == $0
  # Check if Rails server is running for API test
  if ARGV.include?('--api') && system("curl -s http://localhost:3000/health > /dev/null 2>&1")
    PerformanceModeAPITest.run
  else
    PerformanceModeTest.new.run_tests
  end
end
