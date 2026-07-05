# app/services/conversation_orchestrator/response_synthesizer.rb
class ConversationOrchestrator::ResponseSynthesizer
  def self.call(llm_response:, action_results:, prompt_data:)
    new(llm_response: llm_response, action_results: action_results, prompt_data: prompt_data).call
  end

  def initialize(llm_response:, action_results:, prompt_data:)
    @llm_response = llm_response
    @action_results = action_results
    @prompt_data = prompt_data
  end

  def call
    ai_response = generate_final_response
    ServiceResult.success(ai_response)
  rescue => e
    ServiceResult.failure("Response synthesis failed: #{e.message}")
  end

  private

  def generate_final_response
    response_id = SecureRandom.uuid

    # Extract narrative elements from structured output. Guard against a nil
    # response (defense in depth — LlmIntention already substitutes a fallback).
    structured_data = (@llm_response || {}).deep_stringify_keys
    speech = structured_data["speech"]
    speech = "I understand." if speech.blank?

    # actions is a list of { "action_name" => ..., "description" => ... }.
    actions = Array(structured_data["actions"]).select { |a| a.is_a?(Hash) && a["description"].present? }

    persona_obj = Prompts::PersonaLoader.load(@prompt_data[:persona].to_s)
    tts_voice, tts_language = persona_obj.tts_voice

    {
      id: response_id,
      text: speech,
      continue_conversation: structured_data["continue_conversation"] || false,
      inner_monologue: structured_data["inner_monologue"],
      actions: actions,
      success: true,
      speech_text: speech, # kept for downstream (Finalizer/controller) that read :speech_text
      voice: tts_voice,         # short Azure Neural name e.g. "GuyNeural"
      tts_language: tts_language # locale e.g. "en-US" — must match voice
    }
  end
end
