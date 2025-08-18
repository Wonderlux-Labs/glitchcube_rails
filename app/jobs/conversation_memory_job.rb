# frozen_string_literal: true

class ConversationMemoryJob < ApplicationJob
  queue_as :default
  
  def perform(session_id)
    Rails.logger.info "🧠 Creating memories for session: #{session_id}"
    
    conversation = Conversation.find_by(session_id: session_id)
    return unless conversation&.finished?
    
    # Only create memories for conversations with multiple messages
    logs = conversation.conversation_logs.order(:created_at)
    return if logs.count < 2
    
    # Get environmental context
    context = fetch_environmental_context
    
    # Extract memorable insights from the conversation
    memories = extract_conversation_memories(conversation, logs, context)
    
    # Create ConversationMemory records
    memories.each do |memory_data|
      ConversationMemory.create!(
        session_id: session_id,
        summary: memory_data[:summary],
        memory_type: memory_data[:type],
        importance: memory_data[:importance],
        metadata: memory_data[:metadata].to_json
      )
    end
    
    Rails.logger.info "✅ Created #{memories.count} memories for session: #{session_id}"
  end
  
  private
  
  def fetch_environmental_context
    context = {
      time_of_day: time_of_day_description,
      day_of_week: Time.current.strftime('%A'),
      location: 'Black Rock City' # Default for now
    }
    
    # Try to get glitchcube_context sensor data if HA is configured
    if Rails.env.development? || Rails.env.production?
      begin
        # This would use HomeAssistantClient when implemented
        # ha_context = Services::Core::HomeAssistantClient.new.state('sensor.glitchcube_context')
        # context.merge!(extract_ha_context(ha_context)) if ha_context
      rescue => e
        Rails.logger.debug "Could not fetch HA context: #{e.message}"
      end
    end
    
    context
  end
  
  def time_of_day_description
    hour = Time.current.hour
    case hour
    when 0..5 then 'late night'
    when 6..11 then 'morning'  
    when 12..16 then 'afternoon'
    when 17..20 then 'evening'
    else 'night'
    end
  end
  
  def extract_conversation_memories(conversation, logs, context)
    memories = []
    
    # For now, just create a basic conversation record for significant interactions
    if logs.count >= 3
      event_summary = summarize_interaction(conversation, logs, context)
      memories << {
        summary: event_summary,
        type: 'event',
        importance: calculate_basic_importance(logs),
        metadata: {
          extracted_at: Time.current,
          context: context,
          persona: conversation.persona,
          message_count: logs.count,
          duration: calculate_duration(logs)
        }
      }
    end
    
    # TODO: Implement proper LLM-based preference and context extraction
    # TODO: Add GPS location data when available
    # TODO: Add environmental context from sensor.glitchcube_context
    
    memories
  end
  
  def extract_preferences(user_messages, ai_responses)
    # Basic implementation - just store that a conversation happened
    # TODO: Implement proper LLM-based memory extraction later
    []
  end
  
  def has_high_engagement(logs)
    # Consider high engagement if:
    # - Long messages (avg > 50 chars)
    # - Tools were used
    # - Multiple back-and-forth exchanges
    
    avg_length = logs.map { |log| log.user_message.length }.sum / logs.count.to_f
    has_tools = logs.any? { |log| log.ai_response.include?('[THOUGHTS:') }
    
    avg_length > 50 || has_tools || logs.count >= 3
  end
  
  def summarize_interaction(conversation, logs, context)
    first_message = logs.first.user_message.truncate(100)
    persona = conversation.persona.capitalize
    
    summary = "#{context[:time_of_day].capitalize} interaction with #{persona} persona"
    summary += " at #{context[:location]}" if context[:location] != 'Black Rock City'
    summary += ". Started with: \"#{first_message}\""
    
    if logs.count >= 5
      summary += ". Extended #{logs.count}-message conversation"
    end
    
    summary
  end
  
  def calculate_basic_importance(logs)
    # Simple importance based on conversation length
    case logs.count
    when 3..4 then 5
    when 5..9 then 6  
    when 10..20 then 7
    else 8
    end
  end
  
  def calculate_duration(logs)
    return 0 if logs.count < 2
    
    start_time = logs.first.created_at
    end_time = logs.last.created_at
    (end_time - start_time).to_i
  end
end