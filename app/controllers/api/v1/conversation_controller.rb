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

  def proactive
    # Extract simple trigger and context strings
    trigger = params[:trigger] || "unknown_trigger"
    context = params[:context] || "no additional context provided"

    # Create a proactive message for the orchestrator
    proactive_message = "[PROACTIVE] #{trigger}: #{context}"

    Rails.logger.info "🤖 Processing proactive conversation: #{proactive_message}"

    # Use a default session_id for proactive conversations
    session_id = extract_session_id_from_payload || default_proactive_session_id

    # Build context for proactive conversation
    proactive_context = {
      conversation_id: "proactive_#{SecureRandom.hex(8)}",
      device_id: "cube_proactive_system",
      language: "en",
      voice_interaction: false,
      timestamp: Time.current.iso8601,
      source: "proactive_trigger",
      trigger: trigger,
      context: context
    }

    result = ConversationOrchestrator.new(
      session_id: session_id,
      message: proactive_message,
      context: proactive_context
    ).call

    # Format response in the structure that HASS expects
    formatted_response = format_response_for_hass(result)

    Rails.logger.info "🤖 Proactive response completed: #{trigger}"
    render json: formatted_response

  rescue StandardError => e
    Rails.logger.error "ProactiveConversationController failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # Return error in HASS-compatible format
    render json: {
      success: false,
      error: e.message,
      data: {
        response_type: "error",
        speech_text: "I encountered an error processing the proactive trigger. Please check the system.",
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
    # HASS sends message in this structure (but be careful with proactive calls)
    message = params[:message] || params[:text] || ""

    # Only try to dig into context if it's a hash
    if message.blank? && params[:context].is_a?(Hash)
      message = params.dig(:context, :message) || ""
    end

    message
  end

  def extract_session_id_from_payload
    # HASS sends session_id in context (but in proactive calls, context is a string)
    session_id = if params[:context].is_a?(Hash)
      params.dig(:context, :session_id)
    else
      params[:session_id]
    end

    session_id || default_session_id
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
    return error_response("Invalid orchestrator result") unless orchestrator_result.is_a?(Hash)

    response_data = orchestrator_result[:response] || {}
    return error_response("Invalid response data") unless response_data.is_a?(Hash)

    speech_data = response_data[:speech] || {}
    speech_text = if speech_data.is_a?(Hash)
      speech_data.dig(:plain, :speech) || "I understand."
    else
      "I understand."
    end

    {
      success: true,
      data: {
        response_type: determine_response_type(orchestrator_result),
        response: speech_text,
        speech_text: speech_text,
        continue_conversation: orchestrator_result[:continue_conversation] || false,
        # Include metadata for debugging
        metadata: (speech_data.is_a?(Hash) ? speech_data.dig(:plain, :extra_data) : nil) || {}
      }
    }
  end

  def error_response(message)
    {
      success: false,
      error: message,
      data: {
        response_type: "error",
        speech_text: "I encountered an error. Please try again.",
        error_details: message
      }
    }
  end

  def determine_response_type(orchestrator_result)
    # Check if async tools were queued
    return "normal" unless orchestrator_result.is_a?(Hash)
    return "normal" unless orchestrator_result[:response].is_a?(Hash)

    metadata = orchestrator_result.dig(:response, :speech, :plain, :extra_data) || {}
    return "normal" unless metadata.is_a?(Hash)

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

  def default_proactive_session_id
    @default_proactive_session_id ||= Digest::SHA256.hexdigest(
      "cube_proactive_#{ENV.fetch('INSTALLATION_ID', 'default')}"
    )[0..16]
  end
end
