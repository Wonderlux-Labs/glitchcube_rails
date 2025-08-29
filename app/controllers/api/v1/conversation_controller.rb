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
    # Extract trigger and context parameters
    trigger_type = params[:trigger] || "unknown_trigger"
    context_data = params[:context] || {}

    Rails.logger.info "🤖 Generating proactive message for trigger: #{trigger_type}"

    begin
      # Generate contextual message using LLM
      result = ProactiveMessageService.generate(
        trigger_type: trigger_type,
        context: context_data
      )

      # Skip announcement if determined inappropriate 
      unless result[:should_announce]
        Rails.logger.info "🤫 Skipping proactive announcement (not appropriate)"
        render json: { success: true, skipped: true }
        return
      end

      # Use the generated message and persona-specific satellite
      ha_response = HomeAssistantService.call_service(
        "assist_satellite",
        "start_conversation",
        {
          entity_id: result[:satellite_entity],
          start_message: result[:message],
          extra_system_prompt: "You are responding to a proactive trigger as #{result[:persona]}. Be engaging and helpful."
        }
      )

      Rails.logger.info "✅ Proactive conversation started as #{result[:persona]} via #{result[:satellite_entity]}"

      render json: {
        success: true,
        persona: result[:persona],
        message: result[:message]
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

  def persona_arrival
    persona_id = params[:persona_id] || params[:persona]
    current_goal = params[:current_goal]
    current_mood = params[:current_mood] || "neutral"
    
    unless persona_id
      render json: { success: false, error: "persona_id required" }, status: 400
      return
    end

    Rails.logger.info "🎭 Persona arrival announcement for: #{persona_id}"

    begin
      persona_instance = get_persona_instance(persona_id)
      unless persona_instance
        render json: { success: false, error: "Unknown persona: #{persona_id}" }, status: 400
        return
      end

      # Get system prompt
      system_prompt = get_persona_system_prompt(persona_instance)
      
      # Build context
      context = build_arrival_context(current_goal, current_mood)
      
      # Create arrival prompt
      user_message = "You've just become the active persona! Give a brief 3-second introduction that shows your personality and acknowledges the current situation. Context: #{context}"

      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: user_message }
      ]

      # Call LLM for announcement
      response = LlmService.call_with_structured_output(
        messages: messages,
        response_format: "text",
        model: Rails.configuration.default_ai_model,
        temperature: 0.9
      )

      announcement = response.content || "Hello, I'm #{persona_id}!"
      
      # Get persona voice
      persona_voice = get_persona_voice(persona_id)
      
      # Announce via Home Assistant
      HomeAssistantService.call_service(
        "music_assistant",
        "announce", 
        {
          message: announcement,
          voice: persona_voice,
          entity_id: "media_player.square_voice"
        }
      )

      Rails.logger.info "🎤 #{persona_id} arrival: #{announcement[0..100]}..."
      
      render json: {
        success: true,
        persona_id: persona_id,
        announcement: announcement,
        voice: persona_voice
      }

    rescue StandardError => e
      Rails.logger.error "❌ Persona arrival failed: #{e.message}"
      render json: { success: false, error: e.message }, status: 500
    end
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
        # Include configurable delay when continuing conversation
        continue_delay: continue_conversation ? Rails.configuration.conversation_continue_delay.to_i : nil,
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

  # Get persona instance from ID
  def get_persona_instance(persona_id)
    case persona_id.to_sym
    when :buddy then Personas::BuddyPersona.new
    when :jax then Personas::JaxPersona.new
    when :sparkle then Personas::SparklePersona.new
    when :zorp then Personas::ZorpPersona.new
    when :lomi then Personas::LomiPersona.new
    when :crash then Personas::CrashPersona.new
    when :neon then Personas::NeonPersona.new
    when :mobius then Personas::MobiusPersona.new
    when :thecube then Personas::ThecubePersona.new
    else
      Rails.logger.warn "⚠️ Unknown persona: #{persona_id}"
      nil
    end
  end

  # Get system prompt from persona
  def get_persona_system_prompt(persona_instance)
    result = persona_instance.process_message("", {})
    result[:system_prompt] || "You are #{persona_instance.name}, a unique AI persona in the GlitchCube."
  rescue StandardError => e
    Rails.logger.error "Failed to get system prompt: #{e.message}"
    "You are #{persona_instance.name}, a unique AI persona in the GlitchCube."
  end

  # Get persona voice ID from config
  def get_persona_voice(persona_id)
    begin
      config_path = Rails.root.join("lib", "prompts", "personas", "#{persona_id}.yml")
      if File.exist?(config_path)
        config = YAML.load_file(config_path)
        config["voice_id"]
      end
    rescue StandardError => e
      Rails.logger.warn "Failed to load voice for #{persona_id}: #{e.message}"
      nil
    end
  end

  # Build arrival context
  def build_arrival_context(current_goal, current_mood)
    context_parts = []
    context_parts << "Current mood: #{current_mood}" if current_mood.present?
    context_parts << "Current goal: #{current_goal}" if current_goal.present?
    
    # Get basic environment context
    begin
      current_time = Time.current
      time_str = current_time.strftime("%l:%M %p").strip
      context_parts << "Time: #{time_str}"
      
      hour = current_time.hour
      period = case hour
      when 5..11 then "morning"
      when 12..16 then "afternoon" 
      when 17..20 then "evening"
      else "night"
      end
      context_parts << "Period: #{period}"
    rescue
      # Ignore timing errors
    end
    
    context_parts.join(", ")
  end
end
