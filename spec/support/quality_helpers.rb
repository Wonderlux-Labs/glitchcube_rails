module QualityHelpers
  include ActiveJob::TestHelper

  # Calls the conversation LLM for real against a given persona and user input.
  # Uses PromptBuilder to build a realistic system prompt, then calls LlmIntention
  # with the configured ai_model.
  #
  # Returns the NarrativeResponseSchema hash:
  #   { "speech" => "...", "inner_monologue" => "...", "continue_conversation" => true,
  #     "actions" => [ { "action_name" => "cube_light", "description" => "..." } ] }
  #
  # Injects FakeHomeAssistant so no real HASS hardware is needed.
  def run_brain_turn(persona:, user_input:, session_id: nil)
    sid = session_id || "quality_#{persona}_#{SecureRandom.hex(6)}"

    HomeAssistantService.instance = FakeHomeAssistant.new(
      persona: persona.to_s,
      entities: {
        "light.cube_inner" => { "state" => "on", "attributes" => { "brightness" => 200 } },
        "light.cube_outer" => { "state" => "on", "attributes" => { "brightness" => 150 } }
      }
    )

    conversation = Conversation.create!(session_id: sid)
    persona_instance = Prompts::PersonaLoader.load(persona.to_s)

    prompt_result = ConversationOrchestrator::PromptBuilder.call(
      conversation: conversation,
      persona: persona_instance,
      user_message: user_input,
      context: { session_id: sid }
    )
    raise "PromptBuilder failed: #{prompt_result.error}" unless prompt_result.success?

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    llm_result = ConversationOrchestrator::LlmIntention.call(
      prompt_data: prompt_result.data,
      user_message: user_input,
      model: Rails.configuration.ai_model
    )
    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).round(2)

    raise "LlmIntention failed: #{llm_result.error}" unless llm_result.success?

    narrative = llm_result.data[:llm_response]
    Rails.logger.info "[QUALITY] brain turn for #{persona}: #{elapsed}s | speech: #{narrative["speech_text"]&.length} chars"
    narrative
  ensure
    HomeAssistantService.reset_instance!
    Conversation.where(session_id: sid).destroy_all rescue nil
  end
end
