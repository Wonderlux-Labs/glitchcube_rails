# frozen_string_literal: true

module Services
  module Memory
    class MemoryRecallService
      class << self
        # Get relevant memories for injection into conversation
        def get_relevant_memories(location: nil, context: {}, limit: 3) # rubocop:disable Lint/UnusedMethodArgument
          selected_memories = []

          # 1. Get any upcoming events (high priority!)
          upcoming = ::Memory.events_within(24).order(Arel.sql("(data->>'event_time')::timestamp ASC")).first
          selected_memories << upcoming if upcoming

          # 2. Get a location-based memory if we have location
          if location.present?
            location_memory = ::Memory.by_location(location)
                                      .fresh # Less-told stories
                                      .where.not(id: selected_memories.map(&:id))
                                      .first
            selected_memories << location_memory if location_memory
          end

          # 3. Fill remaining slots with recent high-intensity memories
          remaining_slots = limit - selected_memories.size
          if remaining_slots.positive?
            recent_memories = ::Memory.high_intensity
                                      .recent
                                      .fresh
                                      .where.not(id: selected_memories.map(&:id))
                                      .limit(remaining_slots)
            selected_memories.concat(recent_memories)
          end

          # Track recall
          selected_memories.each(&:recall!)

          selected_memories
        end

        # Format memories for conversation injection
        def format_for_context(memories)
          return '' if memories.empty?

          formatted = memories.map do |memory|
            # Add variety to how memories are introduced
            intro = memory_introduction(memory)
            "#{intro} #{memory.content}"
          end

          "\n\nRECENT MEMORIES TO NATURALLY REFERENCE:\n#{formatted.join("\n")}\n"
        end

        # Check if we know a person
        def know_person?(name)
          ::Memory.about_person(name).exists?
        end

        # Get a person's story summary
        def person_summary(name)
          memories = ::Memory.about_person(name)
                             .order(Arel.sql("(data->>'emotional_intensity')::float DESC"))
                             .limit(5)

          return nil if memories.empty?

          locations = memories.map(&:location).compact.uniq
          tags = memories.flat_map(&:tags).tally.sort_by { |_, count| -count }.first(5).map(&:first)

          {
            name: name,
            encounter_count: memories.count,
            locations: locations,
            vibe_tags: tags,
            best_story: memories.first&.content,
            emotional_average: memories.map(&:emotional_intensity).sum / memories.count
          }
        end

        # Get memories about specific people
        def get_people_memories(names, limit: 3)
          return [] if names.blank?

          memories = Memory.about_person(names.first)
          names[1..]&.each do |name|
            memories = memories.or(Memory.about_person(name))
          end

          memories.order(Arel.sql("(data->>'emotional_intensity')::float DESC"))
                  .order(:recall_count)
                  .limit(limit)
                  .tap { |m| m.each(&:recall!) }
        end

        # Get social connections for a person
        def get_social_connections(person_name)
          memories = ::Memory.about_person(person_name)

          connections = {
            name: person_name,
            mentioned_count: memories.count,
            locations: memories.map(&:location).uniq.compact,
            co_mentioned: [],
            stories: []
          }

          # Find who else appears in stories with this person
          people_set = Set.new
          memories.each do |memory|
            people_set.merge(memory.people - [ person_name ])

            # Include brief story snippets
            connections[:stories] << {
              content: memory.content[0..100],
              intensity: memory.emotional_intensity,
              tags: memory.tags
            }
          end

          connections[:co_mentioned] = people_set.to_a
          connections
        end

        # Get trending memories (high intensity, recent, less recalled)
        def get_trending_memories(limit: 5)
          ::Memory.where(created_at: 24.hours.ago..)
                  .high_intensity
                  .fresh # Less-told stories
                  .limit(limit)
        end

        private

        def memory_introduction(memory)
          # Simple intros based on what we have
          if memory.upcoming_event?
            [ 'Oh! Did you hear about', "Don't miss", "There's something happening" ].sample
          elsif memory.location.present?
            [ "Last time at #{memory.location},", "When I was at #{memory.location},", "At #{memory.location}," ].sample
          elsif memory.tags.include?('gossip') || memory.tags.include?('drama')
            [ 'I heard that', 'Someone told me', 'Did you know' ].sample
          elsif memory.tags.include?('wild') || memory.tags.include?('crazy')
            [ "You won't believe this -", 'Something wild happened:', 'Get this -' ].sample
          else
            [ 'That reminds me,', 'Oh!', 'By the way,' ].sample
          end
        end
      end
    end
  end
end
