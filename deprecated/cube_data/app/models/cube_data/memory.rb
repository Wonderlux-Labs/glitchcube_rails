# frozen_string_literal: true

class CubeData::Memory < CubeData
  class << self
    # Update memory statistics
    def update_stats(total_memories, recent_extractions = 0, last_extraction_time = nil)
      write_sensor(
        sensor_id(:memory, :stats),
        total_memories,
        {
          total_count: total_memories,
          recent_extractions: recent_extractions,
          last_extraction: last_extraction_time&.iso8601,
          last_updated: Time.current.iso8601
        }
      )

      Rails.logger.info "🧠 Memory stats updated: #{total_memories} total"
    end

    # Record memory extraction
    def record_extraction(extraction_type, memories_extracted, session_id = nil)
      write_sensor(
        sensor_id(:memory, :last_extraction),
        extraction_type,
        {
          extraction_type: extraction_type,
          memories_extracted: memories_extracted,
          session_id: session_id,
          extracted_at: Time.current.iso8601
        }
      )

      Rails.logger.info "🧠 Memory extraction recorded: #{extraction_type} (#{memories_extracted} memories)"
    end

    # Update total memory count
    def update_total_count(count)
      write_sensor(
        sensor_id(:memory, :total_memories),
        count,
        {
          last_updated: Time.current.iso8601
        }
      )
    end

    # Record recent memories
    def update_recent_memories(memory_summaries, limit = 10)
      recent = memory_summaries.take(limit)

      write_sensor(
        sensor_id(:memory, :recent_memories),
        recent.count,
        {
          memories: recent.map { |m| {
            summary: m.summary&.truncate(100),
            type: m.memory_type,
            importance: m.importance,
            created_at: m.created_at.iso8601
          }},
          last_updated: Time.current.iso8601
        }
      )

      Rails.logger.debug "🧠 Recent memories updated: #{recent.count} memories"
    end

    # Get memory statistics
    def stats
      read_sensor(sensor_id(:memory, :stats))
    end

    # Get total memory count
    def total_count
      stats_data = stats
      stats_data&.dig("state")&.to_i || 0
    end

    # Get recent extractions count
    def recent_extractions
      stats_data = stats
      stats_data&.dig("attributes", "recent_extractions")&.to_i || 0
    end

    # Get last extraction info
    def last_extraction
      read_sensor(sensor_id(:memory, :last_extraction))
    end

    # Get last extraction time
    def last_extraction_time
      extraction_data = last_extraction
      timestamp = extraction_data&.dig("attributes", "extracted_at")
      timestamp ? Time.parse(timestamp) : nil
    rescue
      nil
    end

    # Get recent memories data
    def recent_memories
      read_sensor(sensor_id(:memory, :recent_memories))
    end

    # Get recent memory list
    def recent_memory_list
      recent_data = recent_memories
      recent_data&.dig("attributes", "memories") || []
    end

    # Check if memories were extracted recently
    def extracted_recently?(within = 30.minutes)
      last_time = last_extraction_time
      return false unless last_time

      last_time > within.ago
    end

    # Get memory stats summary
    def summary
      {
        total: total_count,
        recent_extractions: recent_extractions,
        last_extraction: last_extraction_time,
        recent_memories: recent_memory_list.count
      }
    end
  end
end
