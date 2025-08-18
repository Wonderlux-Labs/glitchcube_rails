# app/controllers/api/v1/conversation_controller.rb
class Api::V1::ConversationController < Api::V1::BaseController
  # This is the endpoint Home Assistant calls via /api/v1/conversation
  def handle
    # Extract message and context from HASS payload structure
    message = extract_message_from_payload
    context = extract_context_from_payload
    session_id = extract_session_id_from_payload

    Rails.logger.info "🧠 Processing HASS conversation: #{message}"
    Rails.logger.info "📋 Session ID: #{session_id}"
    Rails.logger.info "🔍 Context: #{context}"

    result = ConversationOrchestrator.new(
      session_id: session_id,
      message: message,
      context: context
    ).call

    # Format response in the structure HASS expects
    formatted_response = format_response_for_hass(result)

    Rails.logger.info "📤 Returning to HASS: #{formatted_response}"
    render json: formatted_response

  rescue StandardError => e
    Rails.logger.error "ConversationController#process failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # Return error in HASS-compatible format
    render json: {
      success: false,
      error: e.message,
      data: {
        response_type: "error",
        speech_text: "I'm sorry, I encountered an error processing your request. Please try again.",
        error_details: e.message
      }
    }, status: 500
  end

  def health
    render json: {
      status: "ok",
      version: Rails.application.version || "1.0.0",
      conversation_agent: "cube_conversation",
      orchestrator: "enabled",
      timestamp: Time.current.iso8601
    }
  end

  private

  def extract_message_from_payload
    # HASS sends message in this structure
    params[:message] || params.dig(:context, :message) || params[:text] || ""
  end

  def extract_session_id_from_payload
    # HASS sends session_id in context
    params.dig(:context, :session_id) ||
    params[:session_id] ||
    default_session_id
  end

  def extract_context_from_payload
    context = params[:context] || {}
    ha_context = context[:ha_context] || {}

    {
      conversation_id: context[:conversation_id],
      device_id: context[:device_id],
      language: context[:language] || "en",
      voice_interaction: context[:voice_interaction] || false,
      timestamp: context[:timestamp],
      ha_context: ha_context,
      agent_id: ha_context[:agent_id],
      source: "hass_conversation"
    }
  end

  def format_response_for_hass(orchestrator_result)
    # Format in the structure that HASS conversation agent expects
    response_data = orchestrator_result[:response] || {}

    {
      success: true,
      data: {
        response_type: determine_response_type(orchestrator_result),
        response: response_data[:speech]&.dig(:plain, :speech) || "I understand.",
        speech_text: response_data[:speech]&.dig(:plain, :speech) || "I understand.",
        continue_conversation: orchestrator_result[:continue_conversation] || false,
        # Include metadata for debugging
        metadata: response_data[:speech]&.dig(:plain, :extra_data) || {}
      }
    }
  end

  def determine_response_type(orchestrator_result)
    # Check if async tools were queued
    metadata = orchestrator_result.dig(:response, :speech, :plain, :extra_data) || {}
    async_tools = metadata[:async_tools_queued] || []

    if async_tools.any?
      "immediate_speech_with_background_tools"
    else
      "normal"
    end
  end

  def default_session_id
    @default_session_id ||= Digest::SHA256.hexdigest(
      "cube_installation_#{ENV.fetch('INSTALLATION_ID', 'default')}"
    )[0..16]
  end
end
