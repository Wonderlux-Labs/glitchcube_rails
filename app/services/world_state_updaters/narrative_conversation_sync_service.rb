# app/services/world_state_updaters/narrative_conversation_sync_service.rb

class WorldStateUpdaters::NarrativeConversationSyncService
  class Error < StandardError; end

  def self.sync_latest_conversation
    new.sync_latest_conversation
  end

  def self.sync_conversation(conversation_log)
    new.sync_conversation(conversation_log)
  end

  def initialize
    @ha_service = HomeAssistantService.new
  end

  # Sync the most recent conversation response to world_info sensor
  def sync_latest_conversation
    Rails.logger.info "🌍 Starting narrative conversation sync to world_info sensor"

    latest_log = ConversationLog.recent.first
    return log_no_conversation unless latest_log

    sync_conversation(latest_log)
  end

  # Sync specific conversation log to world_info sensor
  def sync_conversation(conversation_log)
    Rails.logger.info "🌍 Syncing conversation #{conversation_log.id} to world_info sensor"

    narrative_data = extract_narrative_data(conversation_log)
    update_world_info_sensor(narrative_data)

    Rails.logger.info "✅ Successfully synced narrative data to world_info sensor"
  rescue StandardError => e
    Rails.logger.error "❌ Failed to sync narrative data: #{e.message}"
    raise Error, "Narrative sync failed: #{e.message}"
  end

  private

  def extract_narrative_data(conversation_log)
    metadata = parse_metadata(conversation_log.metadata)

    # Get persona from conversation or metadata
    persona = get_persona_from_log(conversation_log, metadata)

    # Extract narrative elements from the conversation
    narrative_data = {
      last_conversation: {
        timestamp: conversation_log.created_at.iso8601,
        session_id: conversation_log.session_id,
        persona: persona,
        user_message: sanitize_message(conversation_log.user_message),
        ai_response: sanitize_message(conversation_log.ai_response),
        message_length: conversation_log.ai_response&.length || 0
      },
      narrative_metadata: {
        inner_thoughts: extract_metadata_field(metadata, "inner_thoughts", "thoughts"),
        current_mood: extract_metadata_field(metadata, "current_mood", "mood"),
        pressing_questions: extract_metadata_field(metadata, "pressing_questions", "questions"),
        goal_progress: extract_metadata_field(metadata, "goal_progress", "goal"),
        continue_conversation: extract_continue_flag(metadata),
        tool_intents: extract_tool_intents(metadata)
      },
      interaction_context: {
        total_messages: ConversationLog.where(session_id: conversation_log.session_id).count,
        conversation_active: determine_if_active(metadata),
        last_updated: Time.current.iso8601
      }
    }

    # Add tool results if present
    if conversation_log.tool_results.present?
      narrative_data[:tool_results] = parse_tool_results(conversation_log.tool_results)
    end

    narrative_data
  end

  def parse_metadata(metadata_string)
    return {} if metadata_string.blank?

    JSON.parse(metadata_string)
  rescue JSON::ParserError => e
    Rails.logger.warn "⚠️ Failed to parse conversation metadata: #{e.message}"
    {}
  end

  def parse_tool_results(tool_results_string)
    return {} if tool_results_string.blank?

    JSON.parse(tool_results_string)
  rescue JSON::ParserError => e
    Rails.logger.warn "⚠️ Failed to parse tool results: #{e.message}"
    {}
  end

  def extract_metadata_field(metadata, *possible_keys)
    possible_keys.each do |key|
      value = metadata[key] || metadata[key.to_s]
      return value if value.present?
    end
    nil
  end

  def extract_continue_flag(metadata)
    continue_flag = extract_metadata_field(metadata, "continue_conversation", "continue")
    return continue_flag if [ true, false ].include?(continue_flag)

    # Try to parse from string values
    continue_string = continue_flag.to_s.downcase
    return true if [ "true", "yes", "1" ].include?(continue_string)
    return false if [ "false", "no", "0" ].include?(continue_string)

    nil
  end

  def extract_tool_intents(metadata)
    tool_intents = extract_metadata_field(metadata, "tool_intents", "tool_intent")
    return tool_intents if tool_intents.is_a?(Array)
    return [ tool_intents ] if tool_intents.is_a?(String) && tool_intents.present?

    []
  end

  def determine_if_active(metadata)
    continue_flag = extract_continue_flag(metadata)
    return continue_flag unless continue_flag.nil?

    # If no explicit flag, assume active if there are tool intents or pressing questions
    tool_intents = extract_tool_intents(metadata)
    questions = extract_metadata_field(metadata, "pressing_questions", "questions")

    tool_intents.any? || questions.present?
  end

  def sanitize_message(message)
    return nil if message.blank?

    # Remove any sensitive information and truncate if needed
    sanitized = message.gsub(/\b\d{3}-\d{2}-\d{4}\b/, "[REDACTED]") # SSNs
                      .gsub(/\b\d{16}\b/, "[REDACTED]") # Credit cards
                      .truncate(500) # Limit length for HA sensor

    sanitized
  end

  def update_world_info_sensor(narrative_data)
    sensor_state = "narrative_updated"

    sensor_attributes = {
      friendly_name: "World Information - Narrative Context",
      last_conversation: narrative_data[:last_conversation],
      narrative_metadata: narrative_data[:narrative_metadata],
      interaction_context: narrative_data[:interaction_context],
      updated_at: Time.current.iso8601
    }

    # Add tool results to attributes if present
    sensor_attributes[:tool_results] = narrative_data[:tool_results] if narrative_data[:tool_results]

    @ha_service.set_entity_state("sensor.world_info", sensor_state, sensor_attributes)

    Rails.logger.info "🌍 Updated sensor.world_info with narrative data from #{narrative_data[:last_conversation][:persona]} persona"
  end

  def get_persona_from_log(conversation_log, metadata)
    # Try to get persona from various sources
    persona = nil

    # Check if conversation_log has persona method/attribute
    persona = conversation_log.persona if conversation_log.respond_to?(:persona)

    # Check metadata for persona information
    persona ||= extract_metadata_field(metadata, "persona", "current_persona", "active_persona")

    # Check associated conversation
    if persona.nil? && conversation_log.conversation
      persona = conversation_log.conversation.persona if conversation_log.conversation.respond_to?(:persona)
    end

    # Default to unknown
    persona || "unknown"
  end

  def log_no_conversation
    Rails.logger.warn "⚠️ No conversation logs found to sync"
    nil
  end
end
