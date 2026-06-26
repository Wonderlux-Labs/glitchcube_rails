module QualityHelpers
  # Calls the brain LLM for real against a given persona and user input.
  # Uses PromptBuilder to build a realistic system prompt, then calls LlmIntention
  # with the configured brain_model.
  #
  # Returns the NarrativeResponseSchema hash:
  #   { "speech_text" => "...", "environment_instruction" => "...",
  #     "inner_thoughts" => "...", "continue_conversation" => true, etc. }
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

    prompt_result = ConversationNewOrchestrator::PromptBuilder.call(
      conversation: conversation,
      persona: persona_instance,
      user_message: user_input,
      context: { session_id: sid }
    )
    raise "PromptBuilder failed: #{prompt_result.error}" unless prompt_result.success?

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    llm_result = ConversationNewOrchestrator::LlmIntention.call(
      prompt_data: prompt_result.data,
      user_message: user_input,
      model: Rails.configuration.brain_model
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

  # Runs a plain-English environment_instruction through the real translator LLM.
  # Returns { result: <formatted string>, service_calls: <what FakeHA recorded> }.
  # The service_calls array tells you which HASS domains the translator actually invoked.
  def run_translator(instruction:, persona: "buddy")
    fake_ha = FakeHomeAssistant.new(
      persona: persona.to_s,
      entities: {
        "light.cube_inner" => { "state" => "on", "attributes" => {} },
        "light.cube_outer" => { "state" => "on", "attributes" => {} }
      }
    )
    HomeAssistantService.instance = fake_ha

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = ToolCallingService
      .new(session_id: "quality_tx_#{SecureRandom.hex(4)}")
      .execute_intent(instruction, { persona: persona })
    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).round(2)

    Rails.logger.info "[QUALITY] translator for '#{instruction[0..50]}': #{elapsed}s"
    { result: result, service_calls: fake_ha.service_calls }
  ensure
    HomeAssistantService.reset_instance!
  end
end
