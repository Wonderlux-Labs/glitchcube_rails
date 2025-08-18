# frozen_string_literal: true

module Jobs
  class MemoryConsolidationJob < BaseJob
    sidekiq_options queue: 'low', retry: 1

    def perform(summary = nil)
      # If no summary provided, consolidate recent memories instead
      unless summary
        Services::Logging::SimpleLogger.info(
          'No summary provided - consolidating recent memories from database',
          tagged: [:memory_consolidation]
        )
        # TODO: Implement periodic memory consolidation from recent conversations
        # This should:
        # 1. Query conversations from the last 6 hours (since cron runs every 6h)
        # 2. Extract memorable insights from each conversation
        # 3. Consolidate them into daily memory documents
        # 4. Update topic-specific documents if needed
        # For now, just return successfully to prevent job failures
        return
      end

      Services::Logging::SimpleLogger.info(
        'Consolidating memories from conversation...',
        tagged: [:memory_consolidation]
      )

      # Extract memorable insights
      memorable_points = extract_memorable_insights(summary)

      return if memorable_points.empty?

      # Update daily memories document
      update_daily_memories(memorable_points, summary)

      # Update topic-specific documents if needed
      update_topic_documents(summary)
    end

    private

    def extract_memorable_insights(summary)
      points = []

      # Add profound or interesting points
      if summary[:key_points]
        profound_keywords = %w[consciousness art creativity existence perception reality dream]

        summary[:key_points].each do |point|
          points << point if profound_keywords.any? { |kw| point.downcase.include?(kw) }
        end
      end

      # Add if visitor had strong emotional response
      points << "Visitor explored multiple emotional states: #{summary[:mood_progression].join(' → ')}" if summary[:mood_progression] && summary[:mood_progression].length > 2

      points
    end

    def update_daily_memories(points, summary)
      date = Date.today.strftime('%Y-%m-%d')
      filename = "daily_memories_#{date}.txt"

      context_service = Services::Memory::ContextRetrievalService.new

      # Read existing memories for today
      existing = read_daily_memories(filename)

      # Append new memories
      updated_content = "#{existing}\n\n#{format_memory_entry(points, summary)}"

      # Save updated memories
      context_service.add_document(
        filename,
        updated_content,
        {
          title: "Daily Memories - #{date}",
          type: 'daily_memory',
          date: date
        }
      )
    end

    def update_topic_documents(summary)
      return unless summary[:topics_discussed]

      context_service = Services::Memory::ContextRetrievalService.new

      # Map topics to document categories
      topic_mappings = {
        'consciousness' => 'consciousness_discussions.txt',
        'art' => 'art_conversations.txt',
        'creativity' => 'creative_explorations.txt',
        'mystery' => 'mysterious_encounters.txt'
      }

      summary[:topics_discussed].each do |topic|
        if (filename = topic_mappings[topic])
          append_to_topic_document(filename, summary, context_service)
        end
      end
    end

    def read_daily_memories(filename)
      context_service = Services::Memory::ContextRetrievalService.new
      path = File.join(Services::Memory::ContextRetrievalService::CONTEXT_DIR, filename)
      return "# Daily Memories\n\n" unless File.exist?(path)

      File.read(path)
    rescue StandardError
      "# Daily Memories\n\n"
    end

    def format_memory_entry(points, summary)
      timestamp = Time.now.strftime('%H:%M')

      entry = "## Conversation at #{timestamp}\n"
      entry += "Duration: #{summary[:duration]} seconds, #{summary[:message_count]} messages\n"
      entry += "Moods explored: #{summary[:mood_progression].join(', ')}\n\n"

      points.each_with_index do |point, i|
        entry += "#{i + 1}. #{point}\n"
      end

      entry
    end

    def append_to_topic_document(filename, summary, context_service)
      path = File.join(Services::Memory::ContextRetrievalService::CONTEXT_DIR, filename)

      existing = File.exist?(path) ? File.read(path) : "# #{filename.gsub('_', ' ').capitalize}\n\n"

      # Add a brief entry about this conversation
      entry = "\n---\n"
      entry += "Date: #{Date.today}\n"
      entry += "Key insight: #{summary[:key_points].first}\n" if summary[:key_points]&.any?

      context_service.add_document(
        filename,
        existing + entry,
        {
          title: filename.gsub('_', ' ').capitalize,
          type: 'topic_memory',
          last_updated: Time.now.iso8601
        }
      )
    end
  end
end
