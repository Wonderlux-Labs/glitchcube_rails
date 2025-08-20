#!/usr/bin/env ruby
# Debug Conversation Script
# Shows exactly what's happening with conversation responses
# Run with: ruby scripts/debug_conversation.rb

require_relative '../config/environment'

puts "🔍 Debug Conversation Script"
puts "=" * 50

# Simple test
prompt = "Hello! How are you doing?"
model = "openai/gpt-4o-mini"
session_id = "debug_#{Time.current.to_i}"

puts "Prompt: #{prompt}"
puts "Model: #{model}"
puts "Session: #{session_id}"
puts "-" * 30

# Enable debug logging
Rails.logger.level = Logger::DEBUG

context = {
  model: model,
  session_id: session_id
}

# Configure for two-tier mode
Rails.configuration.two_tier_tools_enabled = true
Rails.configuration.tool_calling_model = "openai/gpt-4o-mini"

puts "\nCreating orchestrator..."
orchestrator = ConversationOrchestrator.new(
  session_id: session_id,
  message: prompt,
  context: context
)

puts "\nCalling orchestrator..."
response = orchestrator.call

puts "\n" + "=" * 50
puts "RESPONSE ANALYSIS"
puts "=" * 50

puts "Response class: #{response.class}"
puts "Response keys: #{response.keys.inspect if response.respond_to?(:keys)}"

if response.is_a?(Hash)
  puts "\nDETAILED RESPONSE:"
  response.each do |key, value|
    puts "  #{key}: #{value.inspect.truncate(200)}"
  end
end

# Deep inspection of nested response
if response[:response].is_a?(Hash)
  puts "\nNESTED RESPONSE STRUCTURE:"
  def deep_inspect(obj, indent = 2)
    case obj
    when Hash
      obj.each do |k, v|
        puts "#{' ' * indent}#{k}:"
        deep_inspect(v, indent + 2)
      end
    when Array
      obj.each_with_index do |item, i|
        puts "#{' ' * indent}[#{i}]:"
        deep_inspect(item, indent + 2)
      end
    else
      puts "#{' ' * indent}#{obj.inspect.truncate(200)}"
    end
  end
  
  deep_inspect(response[:response])
end

puts "\nSPEECH TEXT CANDIDATES:"
candidates = [
  response.dig(:response_text),
  response.dig(:text), 
  response.dig(:speech_text),
  response.dig("response_text"),
  response.dig("text"),
  response.dig("speech_text"),
  response.dig(:response, :speech, :plain, :speech),
  response.dig("response", "speech", "plain", "speech"),
  response.dig(:response, "speech", "plain", "speech")
].compact.uniq

candidates.each_with_index do |candidate, i|
  puts "  #{i+1}: #{candidate.inspect.truncate(100)}"
end

puts "\nOTHER FIELDS:"
puts "  continue_conversation: #{response.dig(:continue_conversation) || response.dig("continue_conversation")}"
puts "  end_conversation: #{response.dig(:end_conversation) || response.dig("end_conversation")}"
puts "  success_entities: #{(response.dig(:success_entities) || response.dig("success_entities") || []).size} items"
puts "  targets: #{(response.dig(:targets) || response.dig("targets") || []).size} items"

puts "\n🎯 The speech text should be in one of these fields!"
puts "Check your ConversationOrchestrator.format_response_for_hass method"