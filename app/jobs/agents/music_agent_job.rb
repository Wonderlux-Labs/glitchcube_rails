# app/jobs/music_agent_job.rb
module Agents
  class MusicAgentJob < ApplicationJob
  queue_as :default

  def perform(request:, tool_intents:, session_id:, conversation_id:, user_message:)
    Rails.logger.info "🎵 MusicAgentJob starting for session: #{session_id}"
    Rails.logger.info "📝 Music Request: #{request}"

    begin
      # Call Home Assistant's conversation.jukebot API
      response = call_music_conversation_agent(request)

      Rails.logger.info "✅ Music agent response received"
      Rails.logger.info "📄 Response: #{response.inspect}"

      # Store results for next conversation turn (not as interrupting message)
      store_music_results(
        session_id: session_id,
        conversation_id: conversation_id,
        user_message: user_message,
        tool_intents: tool_intents,
        music_response: response
      )

      Rails.logger.info "💾 Music results stored for next conversation turn"

    rescue StandardError => e
      Rails.logger.error "❌ MusicAgentJob failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Store failure for next turn
      store_music_results(
        session_id: session_id,
        conversation_id: conversation_id,
        user_message: user_message,
        tool_intents: tool_intents,
        music_response: nil,
        error: e.message
      )
    end
  end

  private

  def call_music_conversation_agent(request)
    Rails.logger.info "🎵 Calling HA music conversation agent"
    Rails.logger.info "📤 Sending to jukebot: #{request}"

    # Call Home Assistant conversation.jukebot agent
    HomeAssistantService.new.conversation_process(
      text: request,
      agent_id: "conversation.jukebot"
    )
  end

  def store_music_results(session_id:, conversation_id:, user_message:, tool_intents:, music_response:, error: nil)
    # Store results in conversation metadata, not as conversation log entries
    # This avoids interrupting ongoing TTS/conversation

    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    # Get existing pending results or create new array
    existing_metadata = conversation.metadata_json || {}
    pending_results = existing_metadata["pending_ha_results"] || []

    # Create result entry for music
    result_entry = {
      timestamp: Time.current.iso8601,
      user_message: user_message,
      tool_intents: tool_intents,
      music_response: music_response,
      agent_type: "music", # Tag this as music agent result
      error: error,
      processed: false
    }

    # Add to pending results
    pending_results << result_entry

    # Update conversation metadata
    updated_metadata = existing_metadata.merge(
      "pending_ha_results" => pending_results
    )

    conversation.update!(metadata_json: updated_metadata)

    Rails.logger.info "💾 Stored music agent results in conversation metadata (not as conversation log)"
  end
  end
end
