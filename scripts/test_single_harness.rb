#!/usr/bin/env ruby
# Quick test of single conversation with enhanced logging
require_relative '../config/environment'

class QuickTestHarness
  def initialize
    @log_file = $stdout
  end

  def run_test
    prompt = "Hello! What can you do?"
    narrative_model = "openai/gpt-4o-mini"
    tool_model = "openai/gpt-4o-mini"
    
    log_line "🧪 Quick Single Test"
    log_line "Prompt: #{prompt}"
    log_line "Narrative: #{narrative_model}"
    log_line "Tool: #{tool_model}"
    log_line "-" * 40
    
    # Configure for two-tier mode
    original_tool_model = Rails.configuration.try(:tool_calling_model)
    Rails.configuration.tool_calling_model = tool_model
    Rails.configuration.two_tier_tools_enabled = true
    
    session_id = "quick_test_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
    
    context = {
      model: narrative_model,
      session_id: session_id
    }
    
    log_line "Creating orchestrator..."
    orchestrator = ConversationOrchestrator.new(
      session_id: session_id,
      message: prompt,
      context: context
    )
    
    log_line "Calling orchestrator..."
    start_time = Time.current
    response = orchestrator.call
    response_time = Time.current - start_time
    
    log_line "Response received in #{response_time.round(3)}s"
    
    # Parse response
    parsed = parse_response(response)
    
    log_line "\n" + "=" * 50
    log_line "RESULTS:"
    log_line "  Speech: #{parsed[:speech_text]}"
    log_line "  Continue: #{parsed[:continue_conversation]}"
    log_line "  End: #{parsed[:end_conversation]}"
    log_line "  Entities: #{parsed[:success_entities]&.size || 0}"
    log_line "  Targets: #{parsed[:targets]&.size || 0}"
    log_line "=" * 50
    
    # Restore config
    Rails.configuration.tool_calling_model = original_tool_model
    
    if parsed[:speech_text] && parsed[:speech_text] != "No speech text found"
      log_line "\n✅ SUCCESS! Speech text extracted correctly"
      log_line "The test harnesses should now work properly!"
    else
      log_line "\n❌ FAILED! Still not extracting speech text"
      log_line "Need to debug further..."
    end
  end
  
  private
  
  def parse_response(response)
    log_line "\nRAW RESPONSE STRUCTURE:"
    log_line "  Keys: #{response.keys.inspect}"
    
    speech_text = response.dig(:response, :speech, :plain, :speech) ||
                  response.dig("response", "speech", "plain", "speech") ||
                  "No speech text found"
    
    targets = response.dig(:response, :data, :targets) || []
    success_entities = response.dig(:response, :data, :success) || []
    
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
  
  def log_line(message)
    puts message
  end
end

# Run the test
harness = QuickTestHarness.new
harness.run_test