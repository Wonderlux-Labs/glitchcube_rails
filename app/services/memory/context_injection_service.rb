# frozen_string_literal: true

# TODO: SPECS WHEN SENSORS ARE COMPLETE
# Write comprehensive specs once the HA context sensor is fully configured and operational

module Services
  module Memory
    class ContextInjectionService
      def self.inject_context(base_prompt, context)
        new.inject_context(base_prompt, context)
      end

      def self.inject_memories_only(base_prompt, context)
        new.inject_memories_only(base_prompt, context)
      end

      def self.get_current_location
        new.fetch_current_location
      end

      def inject_context(base_prompt, context)
        # Skip context injection if explicitly disabled
        return base_prompt if context[:skip_memories] == true

        # Try to get the unified context sensor (may not exist yet)
        context_sensor = nil
        begin
          ha_service = HomeAssistantService.new
          context_sensor = ha_service.entity('sensor.glitchcube_context')

          # Check if sensor actually exists (HA returns specific structure for non-existent entities)
          if context_sensor.is_a?(Hash) && context_sensor['state'] == 'unavailable'
            context_sensor = nil
            Rails.logger.debug '📝 Context sensor not yet configured in HA'
          end
        rescue StandardError => e
          Rails.logger.debug "📝 Could not fetch context sensor: #{e.message}"
        end

        # Build context from sensor if available
        context_parts = build_context_parts(context_sensor, context)

        # Build final prompt with context
        if context_parts.any?
          context_section = "\n\nCURRENT CONTEXT:\n#{context_parts.join('. ')}"
          final_prompt = "#{base_prompt}#{context_section}"

          Rails.logger.debug "📝 Injected context: #{context_parts.size} parts"

          final_prompt
        else
          Rails.logger.debug '📝 No context to inject'

          base_prompt
        end
      rescue StandardError => e
        puts "Failed to inject context: #{e.message}"
        base_prompt
      end

      # Inject only traditional memories without HA context sensor
      def inject_memories_only(base_prompt, context)
        return base_prompt if context[:skip_memories] == true

        # For now, use ConversationMemory since we don't have the full Memory model yet
        memories = get_conversation_memories(context)

        if memories.any?
          memory_context = format_conversation_memories(memories)
          final_prompt = "#{base_prompt}#{memory_context}"

          Rails.logger.info "📝 Injected #{memories.size} conversation memories"

          final_prompt
        else
          Rails.logger.info '📝 No memories to inject'

          base_prompt
        end
      rescue StandardError => e
        Rails.logger.warn "Failed to inject memories: #{e.message}"
        base_prompt
      end

      private

      def build_context_parts(context_sensor, context)
        context_parts = []

        # Ensure context_sensor is a Hash with proper structure
        if context_sensor.is_a?(Hash)
          # BASIC TIME CONTEXT - Always include this first
          time_of_day = context_sensor.dig('attributes', 'time_of_day')
          day_of_week = context_sensor.dig('attributes', 'day_of_week')
          location = context_sensor.dig('attributes', 'current_location')
          
          if time_of_day || day_of_week
            time_parts = []
            time_parts << "It is #{time_of_day}" if time_of_day
            time_parts << "on #{day_of_week}" if day_of_week
            time_parts << "at #{location}" if location
            context_parts << time_parts.join(' ')
          end
          
          # Priority order - urgent needs first
          if (needs = context_sensor.dig('attributes', 'current_needs')) && needs.to_s.include?('URGENT')
            context_parts << "URGENT: #{needs}"
          end

          # Recent context
          if (summary_1hr = context_sensor.dig('attributes', 'summary_1hr'))
            context_parts << "Last hour: #{summary_1hr}"
          end

          # Upcoming events
          if (events = context_sensor.dig('attributes', 'upcoming_events'))
            context_parts << "Coming up: #{events}"
          end

          # Only add broader context if room
          if (context_parts.join('. ').length < 500) && (summary_4hr = context_sensor.dig('attributes', 'summary_4hr'))
            context_parts << summary_4hr
          end
        end

        # Add traditional memory system if available
        add_memory_context(context_parts, context)

        context_parts
      end

      def add_memory_context(context_parts, context)
        location = context[:location] || fetch_current_location
        memories = Services::Memory::MemoryRecallService.get_relevant_memories(
          location: location,
          context: context,
          limit: 2
        )

        if memories.any?
          memory_context = Services::Memory::MemoryRecallService.format_for_context(memories)
          context_parts << memory_context.strip.gsub(/^RECENT MEMORIES TO NATURALLY REFERENCE:\s*/, '')
        end
      rescue StandardError => e
        Rails.logger.warn "Failed to add memory context: #{e.message}"
      end

      def fetch_current_location
        # For now, return a default location since GPS service isn't implemented
        'Black Rock City'
      rescue StandardError
        nil
      end
      
      def get_conversation_memories(context)
        # Get recent high-importance memories from OTHER sessions (exclude current)
        memories = ConversationMemory.high_importance
                                   .recent
        
        # Exclude current session since LLM has full conversation history
        if context[:session_id]
          memories = memories.where.not(session_id: context[:session_id])
        end
        
        memories.limit(3)
      end
      
      def format_conversation_memories(memories)
        return '' if memories.empty?

        formatted = memories.map do |memory|
          "#{memory.memory_type.upcase}: #{memory.summary}"
        end

        "\n\nRECENT MEMORIES:\n#{formatted.join("\n")}\n"
      end
    end
  end
end
