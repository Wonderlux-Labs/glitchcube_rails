#!/usr/bin/env ruby
# Test the sequential numbering system
require_relative '../config/environment'

Dir.mkdir('logs') unless Dir.exist?('logs')
Dir.mkdir('logs/model_tests') unless Dir.exist?('logs/model_tests')

def find_next_run_number(prefix = "test_run")
  existing_files = Dir.glob("logs/model_tests/#{prefix}_*.log")
  puts "Found existing files: #{existing_files.inspect}"
  
  if existing_files.empty?
    1
  else
    numbers = existing_files.map do |file|
      match = file.match(/#{prefix}_(\d+)\.log/)
      puts "  Checking #{file}: match = #{match&.captures}"
      match ? match[1].to_i : 0
    end
    puts "  Numbers found: #{numbers.inspect}"
    numbers.max + 1
  end
end

puts "Testing basic test_run numbering:"
next_basic = find_next_run_number("test_run")
puts "Next basic number: #{next_basic}"

puts "\nTesting enhanced numbering:"
next_enhanced = find_next_run_number("enhanced_test_run")
puts "Next enhanced number: #{next_enhanced}"

# Create test files to verify incrementing
puts "\nCreating test files..."
File.write("logs/model_tests/test_run_#{next_basic}.log", "test")
File.write("logs/model_tests/enhanced_test_run_#{next_enhanced}.log", "test")

puts "After creating files:"
puts "Next basic: #{find_next_run_number("test_run")}"
puts "Next enhanced: #{find_next_run_number("enhanced_test_run")}"