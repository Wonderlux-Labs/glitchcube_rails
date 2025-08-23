# app/controllers/api/v1/conversation_controller.rb
class Api::V1::ConversationController < Api::V1::BaseController
  # This is the endpoint Home Assistant calls via /api/v1/conversation
  def handle
    # Extract message and context from HASS payload structure
    message = extract_message_from_payload
    context = extract_context_from_payload
    session_id = extract_session_id_from_payload

    # Check cube mode
    begin
      cube_mode_entity = HomeAssistantService.entity_state('sensor.cube_mode')
      context[:cube_mode] = cube_mode_entity['state'] if cube_mode_entity
      Rails.logger.info "🔋 Cube mode is: #{context[:cube_mode]}" if context[:cube_mode]
    rescue HomeAssistantService::Error => e
      Rails.logger.warn "⚠️ Could not fetch sensor.cube_mode state: #{e.message}"
    end

    Rails.logger.info "🧠 Processing HASS conversation: #{message}"
    Rails.logger.info "📋 Session ID: #{session_id}"
    Rails.logger.info "🔍 Context: #{context}"

    Rails.logger.info "🔧 Using ConversationNewOrchestrator"

    result = ConversationNewOrchestrator.new(
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
    satellite_entity = params[:satellite_entity] || "assist_satellite.square_voice"

    # Create a proactive message for the HA conversation pipeline
    proactive_message = "[PROACTIVE] #{trigger}: #{context}"

    Rails.logger.info "🤖 Starting proactive conversation via HA satellite: #{proactive_message}"

    begin
      # Call assist_satellite.start_conversation to trigger proper TTS flow
      ha_response = HomeAssistantService.call_service(
        "assist_satellite",
        "start_conversation",
        {
          entity_id: satellite_entity,
          start_message: proactive_message,
          extra_system_prompt: "You are responding to a proactive trigger. Be engaging and helpful."
        }
      )

      Rails.logger.info "✅ Proactive conversation started successfully via #{satellite_entity}"

      render json: {
        success: true
      }

    rescue HomeAssistantService::Error => e
      Rails.logger.error "❌ Failed to start proactive conversation: #{e.message}"

      render json: {
        success: false,
        error: "Failed to start conversation: #{e.message}",
        data: {
          response_type: "error",
          satellite_entity: satellite_entity,
          message: proactive_message
        }
      }
    end

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
        # Include metadata for debugging
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
    # Check if this is a proactive conversation that should trigger immediate speech
    return "immediate_speech_with_background_tools" if @context&.dig(:source) == "proactive_trigger"

    # Check if orchestrator indicates async tools are running
    return "immediate_speech_with_background_tools" if orchestrator_result&.dig(:async_tools_pending)

    "normal"
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
