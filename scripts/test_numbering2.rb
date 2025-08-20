#!/usr/bin/env ruby
# Test the updated sequential numbering system

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
      if match
        number = match[1].to_i
        puts "  Checking #{file}: number = #{number} (#{number <= 9999 ? 'valid' : 'timestamp, ignored'})"
        # Only count files with reasonable sequential numbers (1-9999), ignore timestamps
        number <= 9999 ? number : 0
      else
        puts "  Checking #{file}: no match"
        0
      end
    end.select { |n| n > 0 }
    
    puts "  Valid numbers found: #{numbers.inspect}"
    numbers.empty? ? 1 : numbers.max + 1
  end
end

puts "Testing updated numbering system:"
puts "Next test_run number: #{find_next_run_number("test_run")}"
puts "Next enhanced_test_run number: #{find_next_run_number("enhanced_test_run")}"