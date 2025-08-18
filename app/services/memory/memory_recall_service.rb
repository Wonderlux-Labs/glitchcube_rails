# frozen_string_literal: true

module Services
  module Memory
    class MemoryRecallService
      class << self
        # Get relevant memories for injection into conversation
        def get_relevant_memories(location: nil, context: {}, limit: 3)
          selected_memories = []

          # 1. Get location-related memories if we have location
          if location.present?
            location_memories = ConversationMemory.high_importance
                                                  .recent
                                                  .limit(2)
                                                  .select { |memory| 
                                                    metadata = JSON.parse(memory.metadata || '{}')
                                                    locations = metadata['locations'] || []
                                                    locations.any? { |loc| loc.downcase.include?(location.downcase) }
                                                  }
            selected_memories.concat(location_memories)
          end

          # 2. Fill remaining slots with recent high-importance memories
          remaining_slots = limit - selected_memories.size
          if remaining_slots.positive?
            recent_memories = ConversationMemory.high_importance
                                                .recent
                                                .where.not(id: selected_memories.map(&:id))
                                                .limit(remaining_slots)
            selected_memories.concat(recent_memories)
          end

          selected_memories.uniq.take(limit)
        end

        # Get upcoming events for context
        def get_upcoming_events(location: nil, hours: 24)
          scope = Event.upcoming.within_hours(hours).high_importance
          scope = scope.by_location(location) if location.present?
          scope.limit(3)
        end

        # Get location-based memories
        def get_location_memories(location, limit: 3)
          return [] if location.blank?

          ConversationMemory.high_importance
                            .recent
                            .limit(limit * 2) # Get more to filter
                            .select { |memory| 
                              metadata = JSON.parse(memory.metadata || '{}')
                              locations = metadata['locations'] || []
                              locations.any? { |loc| loc.downcase.include?(location.downcase) }
                            }
                            .take(limit)
        end

        # Format memories for conversation injection
        def format_for_context(memories)
          return '' if memories.empty?

          formatted = memories.map do |memory|
            # Add variety to how memories are introduced
            intro = memory_introduction(memory)
            "#{intro} #{memory.summary}"
          end

          "\n\nRECENT MEMORIES TO NATURALLY REFERENCE:\n#{formatted.join("\n")}\n"
        end

        # Get trending memories (high importance, recent)
        def get_trending_memories(limit: 5)
          ConversationMemory.high_importance
                            .recent
                            .limit(limit)
        end

        # Get memories related to specific topics (simple keyword search)
        def get_topic_memories(keywords, limit: 3)
          return [] if keywords.blank?

          keyword_array = keywords.is_a?(Array) ? keywords : [keywords]
          
          ConversationMemory.recent
                            .limit(limit * 3) # Get more to filter
                            .select { |memory|
                              keyword_array.any? { |keyword|
                                memory.summary.downcase.include?(keyword.downcase)
                              }
                            }
                            .take(limit)
        end

        # Get recent high importance memories excluding current session
        def get_recent_memories_excluding_session(session_id, limit: 3)
          scope = ConversationMemory.high_importance.recent
          scope = scope.where.not(session_id: session_id) if session_id.present?
          scope.limit(limit)
        end

        private

        def memory_introduction(memory)
          # Simple intros based on memory type and content
          case memory.memory_type
          when 'event'
            ['That reminds me,', 'Oh!', 'By the way,', 'Speaking of which,'].sample
          when 'preference'
            ['I remember you mentioned', 'You said before that', 'I recall'].sample
          when 'fact'
            ['You know,', 'I learned that', 'Remember,'].sample
          when 'instruction'
            ['You told me to', 'You wanted me to', 'You asked me to'].sample
          else
            ['That reminds me,', 'Oh!', 'By the way,'].sample
          end
        end
      end
    end
  end
end
