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
          ha_client = Services::Core::HomeAssistantClient.new
          context_sensor = ha_client.state('sensor.glitchcube_context')

          # Check if sensor actually exists (HA returns specific structure for non-existent entities)
          if context_sensor.is_a?(Hash) && context_sensor['state'] == 'unavailable'
            context_sensor = nil
            puts '📝 Context sensor not yet configured in HA' if GlitchCube.config.debug?
          end
        rescue StandardError => e
          puts "📝 Could not fetch context sensor: #{e.message}" if GlitchCube.config.debug?
        end

        # Build context from sensor if available
        context_parts = build_context_parts(context_sensor, context)

        # Build final prompt with context
        if context_parts.any?
          context_section = "\n\nCURRENT CONTEXT:\n#{context_parts.join('. ')}"
          final_prompt = "#{base_prompt}#{context_section}"

          puts "📝 Injected context: #{context_parts.size} parts" if GlitchCube.config.debug?

          final_prompt
        else
          puts '📝 No context to inject' if GlitchCube.config.debug?

          base_prompt
        end
      rescue StandardError => e
        puts "Failed to inject context: #{e.message}"
        base_prompt
      end

      # Inject only traditional memories without HA context sensor
      def inject_memories_only(base_prompt, context)
        return base_prompt if context[:skip_memories] == true

        location = context[:location] || fetch_current_location
        memories = Memory::MemoryRecallService.get_relevant_memories(
          location: location,
          context: context,
          limit: 3
        )

        if memories.any?
          memory_context = Memory::MemoryRecallService.format_for_context(memories)
          final_prompt = "#{base_prompt}#{memory_context}"

          puts "📝 Injected #{memories.size} memories" if GlitchCube.config.debug?

          final_prompt
        else
          puts '📝 No memories to inject' if GlitchCube.config.debug?

          base_prompt
        end
      rescue StandardError => e
        puts "Failed to inject memories: #{e.message}"
        base_prompt
      end

      private

      def build_context_parts(context_sensor, context)
        context_parts = []

        # Ensure context_sensor is a Hash with proper structure
        if context_sensor.is_a?(Hash)
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
        memories = Memory::MemoryRecallService.get_relevant_memories(
          location: location,
          context: context,
          limit: 2
        )

        if memories.any?
          memory_context = Memory::MemoryRecallService.format_for_context(memories)
          context_parts << memory_context.strip.gsub(/^CONTEXT:\s*/, '')
        end
      rescue StandardError => e
        puts "Failed to add memory context: #{e.message}"
      end

      def fetch_current_location
        return nil unless GlitchCube.config.home_assistant.url

        gps_service = Gps::GPSTrackingService.new
        location_data = gps_service.current_location

        # Return the address string for memory location matching
        location_data&.dig(:address)
      rescue StandardError
        nil
      end
    end
  end
end
