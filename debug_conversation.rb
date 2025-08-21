#!/usr/bin/env ruby
# Debug conversation parser - run with: rails runner debug_conversation.rb

puts "=== CONVERSATION DEBUG LOG ==="
puts "Session: #{ARGV[0] || 'latest'}"

if ARGV[0]
  logs = ConversationLog.where(session_id: ARGV[0]).order(:created_at)
else
  logs = ConversationLog.order(:created_at).limit(5)
end

logs.each_with_index do |log, i|
  puts "\n--- CONVERSATION #{i+1} ---"
  puts "Session: #{log.session_id}"
  puts "Time: #{log.created_at}"
  puts "User: #{log.user_message[0..100]}#{'...' if log.user_message.length > 100}"
  puts "AI: #{log.ai_response[0..100]}#{'...' if log.ai_response.length > 100}"

  begin
    metadata = JSON.parse(log.metadata)
    tool_results = JSON.parse(log.tool_results) if log.tool_results

    puts "Model: #{metadata['model_used']}"
    puts "Tokens: #{metadata.dig('usage', 'total_tokens')}"

    if tool_results
      puts "Tool Results:"
      tool_results.each do |tool_name, result|
        success = result.is_a?(Hash) ? (result['success'] || result[:success]) : 'unknown'
        error = result.is_a?(Hash) ? (result['error'] || result[:error]) : nil
        puts "  #{tool_name}: #{success ? '✅' : '❌'} #{error}"
      end
    end

    if metadata['sync_tools']&.any?
      puts "Sync Tools: #{metadata['sync_tools'].length}"
    end

    if metadata['async_tools']&.any?
      puts "Async Tools: #{metadata['async_tools'].length}"
    end

  rescue JSON::ParserError => e
    puts "Parse Error: #{e.message}"
  end
end

puts "\n=== END DEBUG LOG ==="
