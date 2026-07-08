# app/services/conversation_orchestrator/action_executor.rb
class ConversationOrchestrator::ActionExecutor
  def self.call(llm_response:, session_id:, conversation_id:, user_message:, persona: nil)
    new(llm_response: llm_response, session_id: session_id, conversation_id: conversation_id, user_message: user_message, persona: persona).call
  end

  def initialize(llm_response:, session_id:, conversation_id:, user_message:, persona: nil)
    @output = llm_response || {}
    @session_id = session_id
    @conversation_id = conversation_id
    @user_message = user_message
    @persona = persona
  end

  def call
    dispatched = dispatch_environment_instruction

    ServiceResult.success({
      sync_results: {},
      dispatched_environment: dispatched
    })
  rescue => e
    ServiceResult.failure("Action execution failed: #{e.message}")
  end

  private

  # The LLM describes environment changes as a list of structured actions,
  # each { "action_name" => "cube_light", "description" => "warm amber, dim" }.
  # The translator takes a single instruction, so we flatten them into one line.
  #
  # NOTE: how tools/actions get executed is being reworked — this keeps the
  # current translator path wired without over-investing in it.
  def environment_instruction
    Array(@output.dig("actions"))
      .select { |a| a.is_a?(Hash) && a["description"].present? }
      .map { |a| [ a["action_name"], a["description"] ].compact_blank.join(": ") }
      .join("; ").presence
  end

  # All environment changes are handed to the Home Assistant conversation agent via
  # EnvironmentDirectorJob — speak first, act async. Returns true if dispatched.
  def dispatch_environment_instruction
    instruction = environment_instruction
    return false if instruction.blank?

    Rails.logger.info "🎬 Dispatching environment instruction: #{instruction}"

    EnvironmentDirectorJob.perform_later(
      instruction: instruction,
      session_id: @session_id,
      conversation_id: @conversation_id,
      user_message: @user_message,
      persona: @persona.to_s.presence
    )
    true
  end
end
