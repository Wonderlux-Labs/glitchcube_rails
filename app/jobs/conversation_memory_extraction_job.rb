# app/jobs/conversation_memory_extraction_job.rb

class ConversationMemoryExtractionJob < ApplicationJob
  queue_as :default
  
  BATCH_SIZE = 10 # Process up to 10 conversations at once
  
  def perform
    return unless Rails.env.production? || Rails.env.development?
    
    Rails.logger.info "🧠 ConversationMemoryExtractionJob starting"
    
    conversations_without_memories = find_conversations_needing_memories
    
    if conversations_without_memories.empty?
      Rails.logger.info "✅ No conversations need memory extraction"
    else
      Rails.logger.info "🔍 Found #{conversations_without_memories.count} conversations needing memory extraction"
      
      conversations_without_memories.in_batches(of: BATCH_SIZE) do |batch|
        extract_memories_for_batch(batch)
      end
    end
    
    Rails.logger.info "✅ ConversationMemoryExtractionJob completed"
  rescue StandardError => e
    Rails.logger.error "❌ ConversationMemoryExtractionJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  private

  def find_conversations_needing_memories
    # Find finished conversations that don't have any memories yet
    Conversation.finished
      .left_joins(:conversation_memories)
      .where(conversation_memories: { id: nil })
      .includes(:conversation_logs)
  end

  def extract_memories_for_batch(conversations)
    Rails.logger.info "🔄 Processing batch of #{conversations.count} conversations"
    
    conversation_data = prepare_conversation_data(conversations)
    return if conversation_data.empty?
    
    memories = extract_memories_with_llm(conversation_data)
    store_extracted_memories(memories)
  rescue StandardError => e
    Rails.logger.error "❌ Batch memory extraction failed: #{e.message}"
  end

  def prepare_conversation_data(conversations)
    conversations.map do |conversation|
      logs = conversation.conversation_logs.chronological
      next if logs.empty?
      
      {
        session_id: conversation.session_id,
        persona: conversation.persona,
        started_at: conversation.started_at,
        ended_at: conversation.ended_at,
        duration: conversation.duration,
        logs: logs.map do |log|
          {
            user_message: log.user_message,
            ai_response: log.ai_response,
            created_at: log.created_at
          }
        end
      }
    end.compact
  end

  def extract_memories_with_llm(conversation_data)
    prompt = build_memory_extraction_prompt(conversation_data)
    
    response = LlmService.generate_text(
      prompt: prompt,
      system_prompt: build_system_prompt,
      model: 'google/gemini-2.5-flash',
      temperature: 0.3,
      max_tokens: 2000
    )
    
    parse_memory_response(response)
  rescue StandardError => e
    Rails.logger.error "❌ LLM memory extraction failed: #{e.message}"
    []
  end

  def build_system_prompt
    <<~PROMPT
      You are a memory extraction system. Analyze multiple conversations and extract pertinent memories.
      
      For each conversation, identify:
      1. **preferences** - User likes, dislikes, choices (importance 1-10)
      2. **facts** - Concrete information about the user's life/world (importance 1-10)  
      3. **instructions** - Things the user wants done or remembered (importance 1-10)
      4. **context** - Important situational details (importance 1-10)
      5. **events** - Significant happenings or outcomes (importance 1-10)
      
      Return JSON array with format:
      [
        {
          "session_id": "session_123",
          "memory_type": "preference",
          "summary": "User prefers morning coffee over tea",
          "importance": 5,
          "metadata": {"extracted_from": "conversation_logs"}
        }
      ]
      
      Only extract memories that are actually useful for future interactions. Skip small talk.
    PROMPT
  end

  def build_memory_extraction_prompt(conversation_data)
    <<~PROMPT
      Extract pertinent memories from these #{conversation_data.length} finished conversations:
      
      #{format_conversations_for_prompt(conversation_data)}
      
      Return only valuable memories that would be useful for future interactions.
    PROMPT
  end

  def format_conversations_for_prompt(conversation_data)
    conversation_data.map do |conv|
      <<~CONV
        === Conversation #{conv[:session_id]} ===
        Persona: #{conv[:persona]}
        Duration: #{conv[:duration]&.round(2)} seconds
        Started: #{conv[:started_at]}
        
        Exchanges:
        #{format_conversation_logs(conv[:logs])}
        
      CONV
    end.join("\n")
  end

  def format_conversation_logs(logs)
    logs.map do |log|
      "User: #{log[:user_message]}\nAI: #{log[:ai_response]}\n"
    end.join("\n")
  end

  def parse_memory_response(response)
    JSON.parse(response)
  rescue JSON::ParserError => e
    Rails.logger.error "❌ Failed to parse memory JSON: #{e.message}"
    Rails.logger.error "Response was: #{response}"
    []
  end

  def store_extracted_memories(memories)
    memories.each do |memory_data|
      begin
        ConversationMemory.create!(
          session_id: memory_data['session_id'],
          memory_type: memory_data['memory_type'],
          summary: memory_data['summary'],
          importance: memory_data['importance'],
          metadata: memory_data['metadata']&.to_json
        )
        
        Rails.logger.info "💾 Stored #{memory_data['memory_type']} memory for #{memory_data['session_id']}"
      rescue StandardError => e
        Rails.logger.error "❌ Failed to store memory: #{e.message}"
        Rails.logger.error "Memory data: #{memory_data.inspect}"
      end
    end
  end
end