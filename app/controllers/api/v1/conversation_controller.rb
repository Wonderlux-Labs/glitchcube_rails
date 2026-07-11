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

    Rails.logger.info "🔧 Using ConversationOrchestrator"

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
    message = params[:message] || params[:text] || ""

    # Only try to dig into context if it's hash-like (a plain Hash in specs,
    # ActionController::Parameters for real requests — neither is a Hash per
    # is_a?, so check by duck type instead).
    if message.blank? && params[:context].respond_to?(:dig)
      message = params.dig(:context, :message) || ""
    end

    message
  end

  def extract_session_id_from_payload
    # HASS sends session_id inside the context object
    session_id = if params[:context].respond_to?(:dig)
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

    Rails.logger.info "🔍 Formatting orchestrator result: #{orchestrator_result.inspect}"

    # Handle new direct response structure from orchestrator
    # The orchestrator returns a HASS response object directly
    speech_text = orchestrator_result.dig(:response, :speech, :plain, :speech) ||
                  orchestrator_result.dig(:hass_response, :response) ||
                  orchestrator_result[:text] ||
                  orchestrator_result[:speech_text] ||
                  "I understand."

    Rails.logger.info "📢 Extracted speech text for HA: '#{speech_text}'"

    # Extract continue_conversation from the HASS response structure
    continue_conversation = orchestrator_result[:continue_conversation] ||
                           !orchestrator_result[:end_conversation] ||
                           false

    response = {
      success: true,
      data: {
        response_type: determine_response_type(orchestrator_result),
        response: speech_text,
        speech_text: speech_text,
        continue_conversation: continue_conversation,
        end_conversation: !continue_conversation,
        continue_delay: continue_conversation ? 3 : nil,
        voice: orchestrator_result[:voice],
        tts_language: orchestrator_result[:tts_language],
        metadata: {
          orchestrator_keys: orchestrator_result.keys,
          response_extraction_path: "checking multiple paths for speech text"
        }
      }
    }

    Rails.logger.info "📤 Final HASS response: #{response}"
    response
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
    # Check if orchestrator indicates async tools are running
    return "immediate_speech_with_background_tools" if orchestrator_result&.dig(:async_tools_pending)

    "normal"
  end

  def default_session_id
    @default_session_id ||= Digest::SHA256.hexdigest(
      "cube_installation_#{ENV.fetch('INSTALLATION_ID', 'default')}"
    )[0..16]
  end
end
