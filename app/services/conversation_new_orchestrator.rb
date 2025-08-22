# app/services/conversation_new_orchestrator.rb
class ConversationNewOrchestrator
  # Define component-specific error classes for better tracking
  class SetupError < StandardError; end
  class LlmError < StandardError; end
  class ActionError < StandardError; end
  class SynthesisError < StandardError; end
  class FinalizerError < StandardError; end

  def initialize(session_id:, message:, context: {})
    @message = message
    @initial_session_id = session_id
    @context = context
    @state = {} # A hash to hold state as we move through the steps
  end

  # The main entry point that executes the conversation flow step-by-step.
  def call
    Rails.logger.info "🧠 New Orchestration started for message: '#{@message}'"

    # The entire flow is wrapped in a transaction to ensure data consistency
    result = ActiveRecord::Base.transaction do
      begin
        run_setup
        run_pre_llm_checks
        run_llm_intention_call
        run_action_execution
        run_response_synthesis
        run_finalization
      rescue => e
        # Catches exceptions from any step and formats a standard error response.
        # Let the transaction rollback happen, then return error response
        raise e
      end
    end

    Rails.logger.info "✅ New Orchestration finished."
    result
  rescue => e
    # Handle errors outside transaction to avoid rollback of error response
    log_and_handle_error(e)
  end

  private

  # Step 1: Set up the conversation, session, and persona.
  def run_setup
    setup_result = Setup.call(session_id: @initial_session_id, context: @context)
    raise SetupError, setup_result.error unless setup_result.success?
    @state.merge!(setup_result.data) # Populates @state with :conversation, :persona, :session_id
  end

  # Step 2: Perform checks before the main LLM call.
  def run_pre_llm_checks
    # Stop active performance mode if necessary.
    if PerformanceModeService.get_active_performance(@state[:session_id])
      PerformanceModeService.stop_active_performance(@state[:session_id], "conversation_interrupted")
    end

    # Build the prompt for the LLM.
    prompt_result = PromptBuilder.call(
      conversation: @state[:conversation],
      persona: @state[:persona],
      user_message: @message,
      context: @context.merge(session_id: @state[:session_id])
    )
    raise LlmError, prompt_result.error unless prompt_result.success?
    @state[:prompt_data] = prompt_result.data
  end

  # Step 3: Call the LLM to get its narrative and intended actions.
  def run_llm_intention_call
    model = @context[:model] || determine_model_for_conversation
    llm_result = LlmIntention.call(
      prompt_data: @state[:prompt_data],
      user_message: @message,
      model: model
    )
    raise LlmError, llm_result.error unless llm_result.success?
    @state[:llm_response] = llm_result.data[:llm_response]
  end

  def determine_model_for_conversation
    # Use model from context, persona preference, or default
    @context[:model] ||
    get_persona_preferred_model ||
    Rails.configuration.default_ai_model
  end

  def get_persona_preferred_model
    # TODO: Different personas might prefer different models
    # For now, all use default
    # Future: return persona-specific models for different capabilities
    nil
  end

  # Step 4: Execute the tools and actions identified by the LLM.
  def run_action_execution
    action_result = ActionExecutor.call(
      llm_response: @state[:llm_response],
      session_id: @state[:session_id],
      conversation_id: @state[:conversation].id,
      user_message: @message
    )
    raise ActionError, action_result.error unless action_result.success?
    @state[:action_results] = action_result.data
  end

  # Step 5: Synthesize a final, user-facing response from all gathered data.
  def run_response_synthesis
    synthesis_result = ResponseSynthesizer.call(
      llm_response: @state[:llm_response],
      action_results: @state[:action_results],
      prompt_data: @state[:prompt_data]
    )
    raise SynthesisError, synthesis_result.error unless synthesis_result.success?
    @state[:ai_response] = synthesis_result.data
  end

  # Step 6: Log everything, save state, and format the final output.
  def run_finalization
    finalizer_result = Finalizer.call(
      state: @state,
      user_message: @message
    )
    raise FinalizerError, finalizer_result.error unless finalizer_result.success?
    finalizer_result.data[:hass_response]
  end

  # Centralized error handling and logging.
  def log_and_handle_error(e)
    Rails.logger.error "❌ New Orchestration failed: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    # Return a generic, safe response to the client (e.g., Home Assistant)
    ConversationResponse.error(
      "Sorry, I encountered a problem while processing your request.",
      conversation_id: @state[:session_id] || @initial_session_id
    ).to_home_assistant_response
  end
end
