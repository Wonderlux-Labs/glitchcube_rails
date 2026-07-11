# app/services/conversation_orchestrator.rb
class ConversationOrchestrator
  # OpenRouter model-fallback chain for the brain call. Passing an array makes the
  # open_router_enhanced gem send `models: [...]` + `route: "fallback"`, so OpenRouter
  # only drops to the next model when the previous one *errors* (provider down, etc.) —
  # not on a merely weak reply. The primary is the configured `ai_model`; append more
  # fallbacks here as we vet them.
  FALLBACK_MODELS = [ "deepseek/deepseek-v4-flash" ].freeze

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
    Rails.logger.info "🧠 Orchestration started for message: '#{@message}'"

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

    Rails.logger.info "✅ Orchestration finished."
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

    # Refresh the cube's "look" for this turn — fire-and-forget; the job throttles
    # itself (skips unless the description is empty or stale), so enqueueing every
    # turn is cheap. The description lands mid-turn and is in the prompt next round.
    # Contained because it's genuinely optional: a camera problem (or an inline
    # adapter running the job right here, as smoke tests do) must never fail the turn.
    # (The HASS-side kill switch, input_boolean.disable_camera, is checked in the
    # job itself — it's async there, so the HASS read is free.)
    begin
      CameraDescriptionJob.perform_later unless Rails.configuration.disable_camera
    rescue => e
      Rails.logger.warn "📷 Camera refresh failed (turn continues): #{e.class} - #{e.message}"
    end
  end

  # Step 2: Perform checks before the main LLM call.
  def run_pre_llm_checks
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
    @state[:usage] = llm_result.data[:usage]
  end

  def determine_model_for_conversation
    # A per-call override (context[:model]) wins — handy for smoke-testing a
    # different model without touching config — otherwise the configured model
    # followed by its fallback chain (see FALLBACK_MODELS).
    return @context[:model] if @context[:model]

    [ Rails.configuration.ai_model, *FALLBACK_MODELS ].uniq
  end

  # Step 4: Execute the tools and actions identified by the LLM.
  def run_action_execution
    action_result = ActionExecutor.call(
      llm_response: @state[:llm_response],
      session_id: @state[:session_id],
      conversation_id: @state[:conversation].id,
      user_message: @message,
      persona: @state[:persona]
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
    Rails.logger.error "❌ Orchestration failed: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    # Return a generic, safe response to the client (e.g., Home Assistant)
    ConversationResponse.error(
      "Sorry, I encountered a problem while processing your request.",
      conversation_id: @state[:session_id] || @initial_session_id
    ).to_home_assistant_response
  end
end
