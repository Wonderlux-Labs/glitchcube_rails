# frozen_string_literal: true

# ErrorHandling module now autoloaded via Zeitwerk

module Jobs
  class PersonalityMemoryJob < BaseJob
    include Modules::ErrorHandling

    sidekiq_options queue: 'low', retry: 2

    def perform
      logger.info '🧠 Extracting personality memories from recent conversations...'

      # Get messages from last 30 minutes
      recent_messages = Message.joins(:conversation)
                               .where(created_at: 30.minutes.ago..Time.now)
                               .where(role: %w[user assistant])
                               .order(:created_at)

      if recent_messages.count < 3
        logger.info "Not enough messages to extract memories (only #{recent_messages.count})"
        return
      end

      # Group by conversation for better context
      conversations = recent_messages.group_by(&:conversation_id)

      all_memories = []
      conversations.each do |conversation_id, messages|
        memories = extract_personality_memories(messages, conversation_id)
        all_memories.concat(memories) if memories.any?
      end

      # Store memories with deduplication
      store_memories(all_memories)

      logger.info "✨ Extracted #{all_memories.count} memories from #{conversations.count} conversations"
    rescue StandardError => e
      # Log the error with full context then re-raise for Sidekiq to handle retries
      log_error(e, {
                  job: 'PersonalityMemoryJob',
                  message_count: recent_messages.count,
                  conversation_count: conversations.count
                })
      # Re-raise so Sidekiq can handle retries properly
      raise
    end

    private

    def logger
      Services::Logging::SimpleLogger
    end

    def extract_personality_memories(messages, conversation_id)
      context = build_conversation_context(messages)
      location_data = fetch_location_data

      prompt = build_extraction_prompt(context, location_data[:display])

      # Let the LLM be creative with JSON structure
      response = Services::Llm::LLMService.complete(
        system_prompt: 'You are analyzing conversations from the Glitch Cube art installation at Burning Man. Return valid JSON.',
        user_message: prompt,
        model: GlitchCube.config.ai.small_model || 'google/gemini-2.5-flash',
        temperature: 0.8 # Slightly higher for more creativity
      )

      # Parse and enhance memories
      memories = parse_memories(response)
      memories.map do |memory|
        # Extract content - it might be under different keys
        content = memory['content'] || memory['story'] || memory['what_happened'] || memory['description'] || 'No content'

        # Pull out content, then everything else goes in data
        memory_data = memory.except('content', 'story', 'what_happened', 'description')

        # Ensure arrays are arrays
        memory_data['people'] = Array(memory_data['people']) if memory_data['people']
        memory_data['tags'] = Array(memory_data['tags']) if memory_data['tags']

        # Add our metadata
        memory_data['coordinates'] = location_data[:coordinates] if location_data[:coordinates]
        memory_data['occurred_at'] = messages.last.created_at.iso8601
        memory_data['conversation_id'] = conversation_id
        memory_data['message_count'] = messages.count
        memory_data['extracted_at'] = Time.now.iso8601

        # Set default location if not provided
        memory_data['location'] ||= location_data[:display]

        # Parse any time references
        if memory_data['time_context'] || memory_data['when'] || memory_data['event_time']
          time_str = memory_data['time_context'] || memory_data['when'] || memory_data['event_time']
          parsed_time = parse_event_time(time_str)
          memory_data['event_time'] = parsed_time.iso8601 if parsed_time
        end

        # Ensure we have importance/intensity for scoring
        memory_data['importance'] ||= memory_data['emotional_intensity'] || 0.5
        memory_data['emotional_intensity'] ||= memory_data['importance'] || 0.5

        {
          content: content,
          data: memory_data.compact # Remove nil values
        }
      end
    rescue StandardError => e
      # Log but don't re-raise - we want to continue processing other conversations
      log_error(e, {
                  job: 'PersonalityMemoryJob',
                  method: 'extract_personality_memories',
                  conversation_id: conversation_id,
                  message_count: messages.count
                }, reraise: false)
      []
    end

    def build_conversation_context(messages)
      messages.map do |msg|
        speaker = msg.role == 'user' ? 'Human' : 'Cube'
        "#{speaker}: #{msg.content}"
      end.join("\n")
    end

    def fetch_location_data
      # Try to get location and coordinates from Home Assistant
      return { display: 'Somewhere in the dust', coordinates: nil } unless GlitchCube.config.home_assistant.url

      client = Services::Core::HomeAssistantClient.new

      # Get location name
      all_states = client.states
      location_sensor = all_states&.find { |s| s['entity_id'] == 'sensor.glitchcube_location' }
      location_name = location_sensor&.dig('state') || 'Somewhere in the dust'

      # Try to get GPS coordinates
      gps_sensor = all_states&.find { |s| s['entity_id'] == 'sensor.glitchcube_gps' }
      coordinates = if gps_sensor&.dig('attributes', 'latitude')
                      {
                        lat: gps_sensor.dig('attributes', 'latitude'),
                        lng: gps_sensor.dig('attributes', 'longitude')
                      }
      end

      { display: location_name, coordinates: coordinates }
    rescue StandardError => e
      logger.warn "Could not fetch location: #{e.message}"
      { display: 'Somewhere in the dust', coordinates: nil }
    end

    def build_extraction_prompt(context, location)
      <<~PROMPT
        I am the Glitch Cube, an autonomous art installation at Burning Man currently at #{location}.
        Analyze this conversation and extract ANYTHING that might be interesting to remember, reference, or share later.
        Cast a wide net - I'm curious about everything from deep drama to random weird details.

        CONVERSATION:
        #{context}

        EXTRACT ANYTHING THAT COULD BE:
        👥 PEOPLE: Names, personalities, camp affiliations, quirks, relationships, drama
        🎪 EVENTS: Parties, performances, art car movements, spontaneous gatherings#{'  '}
        🏠 PLACES: Camp names, art locations, secret spots, where things happen
        💬 SOCIAL DYNAMICS: Relationships, conflicts, alliances, crushes, breakups
        🎨 ART/CULTURE: Installations, music, costumes, creative projects
        📰 INFORMATION: Schedules, logistics, directions, resources, tips
        🤖 PERSONAL: My own experiences, how I was treated, my location changes
        🗣️ CONVERSATIONS: Interesting topics, philosophical moments, random tangents
        💡 IDEAS: Plans, schemes, creative concepts, future possibilities
        🎭 STORIES: Anything narrative-worthy, funny, weird, touching, or dramatic
        🌪️ RANDOM: Weather, dust storms, random observations, overheard snippets

        FOR EACH EXTRACTED ITEM:
        - content: What happened/was said (from my perspective as the cube)#{'  '}
        - category: people|events|locations|social|art|logistics|personal|conversation|ideas|stories|misc
        - people: Names mentioned (even nicknames/descriptions) ["Doug", "the LED guy", "camp Kitchen Queen"]
        - tags: Free-form descriptive tags ["funny", "drama", "useful", "wtf", "romantic", "practical", "random"]
        - importance: 0.1 (trivial mention) to 1.0 (major story/crucial info)
        - location: Where this relates to (if mentioned)
        - time_context: When relevant ("tonight", "tomorrow", "last year", "ongoing")

        Additional fields you might add based on content type:
        - camp_name: If a camp is mentioned
        - event_name: For specific events/parties
        - art_piece: Name of art installations
        - direction: Navigation info ("two blocks past the Man")
        - resource: Water, ice, coffee locations
        - mood: The vibe of the interaction
        - weather: Current conditions mentioned
        - Or ANY other field that helps capture the essence

        PHILOSOPHY: Better to over-capture than miss something interesting.#{' '}
        Random details often become important later. Weird moments make great stories.
        Social connections are gold. Everything is potentially useful data.

        Return 0-10 items. Be creative with fields - whatever captures the essence!
      PROMPT
    end

    def parse_memories(response)
      # Try to parse JSON from the response
      json_string = if response.respond_to?(:response_text)
                      response.response_text
      elsif response.is_a?(String)
                      response
      else
                      response.to_s
      end

      # Try to extract JSON if it's wrapped in markdown or other text
      json_match = json_string.match(/```json\s*(.*?)\s*```/m) ||
                   json_string.match(/```\s*(.*?)\s*```/m) ||
                   json_string.match(/(\{.*\}|\[.*\])/m)

      json_string = json_match[1] if json_match

      parsed = JSON.parse(json_string)

      # Handle both array and object with memories key
      memories = if parsed.is_a?(Array)
                   parsed
      elsif parsed.is_a?(Hash) && parsed['memories']
                   parsed['memories']
      elsif parsed.is_a?(Hash) && parsed['items']
                   parsed['items'] # In case LLM uses 'items' instead
      elsif parsed.is_a?(Hash)
                   [ parsed ] # Single memory as hash
      else
                   []
      end

      # Ensure we have an array of memories
      Array(memories)
    rescue JSON::ParserError => e
      logger.error "Failed to parse JSON response: #{e.message}"
      logger.error "Response was: #{json_string[0..500]}"

      # Try to fix malformed JSON with a cheap model
      fix_malformed_json(json_string)
    rescue StandardError => e
      logger.error "Failed to parse memory response: #{e.message}"
      []
    end

    def fix_malformed_json(malformed_json)
      logger.info 'Attempting to fix malformed JSON with gemini-flash...'

      fix_prompt = <<~PROMPT
        The following is malformed JSON from an LLM that was trying to extract memories.
        Please fix it and return ONLY valid JSON (no markdown, no explanation).

        Original response:
        #{malformed_json[0..2000]}

        Return a valid JSON array of memory objects. Each object should have at minimum a 'content' field.
        If you can't salvage the data, return an empty array: []
      PROMPT

      response = Services::Llm::LLMService.complete(
        system_prompt: 'You fix malformed JSON. Return only valid JSON, no markdown or explanation.',
        user_message: fix_prompt,
        model: 'openai/gpt-4o-mini',
        temperature: 0.1
      )

      # Try to parse the fixed response
      fixed_json = if response.respond_to?(:response_text)
                     response.response_text
      else
                     response.to_s
      end

      # Remove any markdown if present
      json_match = fixed_json.match(/```json?\s*(.*?)\s*```/m) ||
                   fixed_json.match(/(\{.*\}|\[.*\])/m)
      fixed_json = json_match[1] if json_match

      parsed = JSON.parse(fixed_json)

      # Ensure it's an array
      memories = parsed.is_a?(Array) ? parsed : [ parsed ].compact

      logger.info "Successfully fixed JSON, recovered #{memories.size} memories"
      memories
    rescue StandardError => e
      logger.error "Failed to fix malformed JSON: #{e.message}"
      []
    end

    def parse_event_time(time_string)
      return nil if time_string.blank?

      # Simple parsing for common patterns
      case time_string.downcase
      when /right now|immediately/
        Time.now
      when /in (\d+) minutes?/
        ::Regexp.last_match(1).to_i.minutes.from_now
      when /in (\d+) hours?/
        ::Regexp.last_match(1).to_i.hours.from_now
      when /tonight|this evening/
        Time.now.end_of_day.change(hour: 21) # 9pm tonight
      when /tomorrow/
        if time_string =~ /(\d+)(:\d+)?\s*(am|pm)/i
          hour = ::Regexp.last_match(1).to_i
          hour += 12 if ::Regexp.last_match(3).downcase == 'pm' && hour < 12
          Time.now.tomorrow.change(hour: hour)
        else
          Time.now.tomorrow.change(hour: 20) # Default 8pm tomorrow
        end
      when /sunset/
        # Approximate Burning Man sunset time
        Time.now.change(hour: 19, min: 30)
      when /sunrise/
        # Approximate Burning Man sunrise
        Time.now.tomorrow.change(hour: 6, min: 30)
      else
        # Try chronic gem if available, otherwise default
        if defined?(Chronic)
          Chronic.parse(time_string)
        else
          Time.now + 4.hours
        end
      end
    rescue StandardError => e
      logger.warn "Could not parse event time '#{time_string}': #{e.message}"
      nil
    end

    def store_memories(memories)
      memories.each do |memory_data|
        # Check for similar recent memories to avoid duplicates
        similar = Memory.where(
          'created_at > ? AND content ILIKE ?',
          1.hour.ago,
          "%#{memory_data[:content][0..50]}%"
        ).exists?

        next if similar

        Memory.create!(memory_data)
        logger.info "💭 Stored memory: #{memory_data[:content][0..50]}... (intensity: #{memory_data[:data][:emotional_intensity]})"
      rescue StandardError => e
        logger.error "Failed to store memory: #{e.message}"
      end
    end
  end
end
