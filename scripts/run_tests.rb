#!/usr/bin/env ruby
# Test Runner - Choose which test harness to run
# Run with: ruby scripts/run_tests.rb

puts "🤖 GLITCH CUBE TEST HARNESS SELECTOR"
puts "=" * 40
puts "1. Quick Test (6 tests, ~30s)"
puts "2. Enhanced Test (detailed metrics)"
puts "3. Model Test (full auto model selection)"
puts "=" * 40
print "Choose test type (1-3): "

choice = gets.chomp

case choice
when "1"
  puts "\n🚀 Running Quick Test Harness..."
  system("ruby scripts/quick_test_harness.rb")
when "2"
  puts "\n🚀 Running Enhanced Test Harness..."
  system("ruby scripts/enhanced_model_test_harness.rb")
when "3"
  puts "\n🚀 Running Model Test Harness..."
  system("ruby scripts/model_test_harness.rb")
else
  puts "Invalid choice. Running quick test as default..."
  system("ruby scripts/quick_test_harness.rb")
end
