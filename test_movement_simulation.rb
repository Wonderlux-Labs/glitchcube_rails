#!/usr/bin/env ruby
# Test script to verify GPS movement simulation

require 'net/http'
require 'json'
require 'uri'

# Configuration
BASE_URL = "http://localhost:3000/api/v1"
GPS_SPOOFING = true # Set to true to enable simulation

def test_api_endpoint(endpoint, method = :get, params = {})
  uri = URI("#{BASE_URL}#{endpoint}")
  http = Net::HTTP.new(uri.host, uri.port)

  if method == :post
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = params.to_json
  else
    request = Net::HTTP::Get.new(uri)
    uri.query = URI.encode_www_form(params) unless params.empty?
  end

  response = http.request(request)
  JSON.parse(response.body)
rescue => e
  puts "Error testing #{endpoint}: #{e.message}"
  nil
end

puts "=== GPS Movement Simulation Test ==="
puts

# 1. Check current location
puts "1. Current Location:"
location = test_api_endpoint("/gps/location")
puts location ? "   Lat: #{location['lat']}, Lng: #{location['lng']}" : "   Failed to get location"
puts

# 2. Check movement status
puts "2. Movement Status:"
status = test_api_endpoint("/gps/movement_status")
if status
  puts "   Moving: #{status['is_moving']}"
  puts "   Destination: #{status['destination'] || 'None'}"
  puts "   Distance remaining: #{status['distance_remaining'] || 'N/A'}"
end
puts

# 3. Start movement to random destination
puts "3. Starting Movement:"
movement = test_api_endpoint("/gps/simulate_movement", :post)
puts movement ? "   #{movement['message']}" : "   Failed to start movement"
puts

# 4. Check movement status again
puts "4. Movement Status After Start:"
status = test_api_endpoint("/gps/movement_status")
if status
  puts "   Moving: #{status['is_moving']}"
  puts "   Destination: #{status['destination'] || 'None'}"
  puts "   Distance remaining: #{status['distance_remaining'] || 'N/A'}"
end
puts

# 5. Get landmarks for destination setting
puts "5. Available Landmarks:"
landmarks = test_api_endpoint("/gps/landmarks")
if landmarks && landmarks['landmarks']
  puts "   Found #{landmarks['landmarks'].length} landmarks"
  first_few = landmarks['landmarks'].first(3)
  first_few.each do |landmark|
    puts "   - #{landmark['name']} (#{landmark['type']})"
  end
end
puts

# 6. Test setting specific destination (if landmarks exist)
if landmarks && landmarks['landmarks'] && !landmarks['landmarks'].empty?
  target_landmark = landmarks['landmarks'].first
  puts "6. Setting Destination to #{target_landmark['name']}:"
  destination = test_api_endpoint("/gps/set_destination", :post, { landmark: target_landmark['name'] })
  puts destination ? "   #{destination['message']}" : "   Failed to set destination"
  puts
end

# 7. Final movement check
puts "7. Final Movement Status:"
status = test_api_endpoint("/gps/movement_status")
if status
  puts "   Moving: #{status['is_moving']}"
  puts "   Destination: #{status['destination'] || 'None'}"
end
puts

puts "=== Test Complete ==="
puts
puts "To manually test movement:"
puts "1. Start Rails server: rails server"
puts "2. Enable GPS spoofing in config if not already enabled"
puts "3. Use the endpoints above to control movement"
puts "4. Monitor logs for background job activity"
