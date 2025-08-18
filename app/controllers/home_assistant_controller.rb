# app/controllers/home_assistant_controller.rb
class HomeAssistantController < ApplicationController
  before_action :authenticate_home_assistant
  
  # Handle conversation.process callbacks from Home Assistant
  def conversation_process
    user_query = params[:text]
    language = params[:language] || 'en'
    conversation_id = params[:conversation_id]
    agent_id = params[:agent_id]
    
    # Build context for the AI response
    context = build_conversation_context(user_query, conversation_id)
    
    # Generate AI response using our ConversationResponse model
    response = ConversationResponse.generate_for_home_assistant(
      user_query,
      context: context,
      model: Rails.configuration.default_ai_model
    )
    
    # Set conversation ID if not provided
    response.conversation_id ||= generate_conversation_id
    response.language = language
    
    # Log the conversation for debugging
    log_conversation(user_query, response, conversation_id)
    
    # Return Home Assistant compatible response
    render json: response.to_home_assistant_response
    
  rescue StandardError => e
    Rails.logger.error "Home Assistant conversation error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    # Return error response in Home Assistant format
    error_response = ConversationResponse.error(
      "I'm sorry, I encountered an error processing your request.",
      conversation_id: conversation_id || generate_conversation_id
    )
    
    render json: error_response.to_home_assistant_response, status: 500
  end
  
  # Health check endpoint for Home Assistant
  def health
    render json: { 
      status: 'ok', 
      service: 'GlitchCube Voice Assistant',
      timestamp: Time.current.iso8601
    }
  end
  
  # Get available entities endpoint (for context building)
  def entities
    entities = HomeAssistantService.entities.map do |entity|
      {
        entity_id: entity['entity_id'],
        name: entity.dig('attributes', 'friendly_name') || entity['entity_id'],
        domain: entity['entity_id'].split('.').first,
        state: entity['state']
      }
    end
    
    render json: { entities: entities }
  rescue StandardError => e
    Rails.logger.error "Error fetching entities: #{e.message}"
    render json: { error: 'Unable to fetch entities' }, status: 500
  end

  private
  
  def authenticate_home_assistant
    # Simple token-based authentication
    token = request.headers['Authorization']&.gsub('Bearer ', '')
    
    unless token == Rails.configuration.home_assistant_token
      render json: { error: 'Unauthorized' }, status: 401
    end
  end
  
  def build_conversation_context(user_query, conversation_id = nil)
    context = {
      timestamp: Time.current.iso8601,
      conversation_id: conversation_id
    }
    
    # Add available entities for context
    begin
      entities = HomeAssistantService.entities.map { |e| e['entity_id'] }
      context[:available_entities] = entities.first(50) # Limit for token usage
    rescue StandardError => e
      Rails.logger.warn "Could not fetch entities for context: #{e.message}"
      context[:available_entities] = []
    end
    
    # Add conversation history if we have a conversation_id
    if conversation_id.present?
      context[:conversation_history] = get_conversation_history(conversation_id)
    end
    
    context
  end
  
  def generate_conversation_id
    "glitchcube_#{SecureRandom.uuid}"
  end
  
  def log_conversation(user_query, response, conversation_id)
    Rails.logger.info "Home Assistant Conversation:"
    Rails.logger.info "  Query: #{user_query}"
    Rails.logger.info "  Response Type: #{response.response_type}"
    Rails.logger.info "  Speech: #{response.speech_plain_text}"
    Rails.logger.info "  Conversation ID: #{conversation_id}"
    Rails.logger.info "  AI Confidence: #{response.ai_confidence}"
  end
  
  def get_conversation_history(conversation_id)
    # TODO: Implement conversation history storage and retrieval
    # This could use the existing Conversation model or a new ConversationHistory model
    []
  end
end