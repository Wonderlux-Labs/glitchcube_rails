# frozen_string_literal: true

# The one and only persona. GlitchCube no longer hosts a roster of characters — it
# is a single amnesiac artifact whose identity is built collaboratively by visitors
# and carried in its character sheet + beliefs (the dynamic self-model). This class
# is the thin seam left of the old persona system: it supplies the static OOC frame
# and the voice from artifact.yml. Everything that changes lives elsewhere.
class Personas::ArtifactPersona < CubePersona
  CONFIG_PATH = Rails.root.join("lib", "prompts", "personas", "artifact.yml")

  def persona_id = :artifact
  def name = persona_config["name"] || "The Artifact"

  def personality_traits = []
  def knowledge_base = []
  def response_style = {}
  def can_handle_topic?(_topic) = true

  def process_message(_message, context = {})
    {
      system_prompt: persona_config["system_prompt"],
      available_tools: [],
      context: context
    }
  end

  def fallback_responses
    persona_config["fallback_responses"] || default_config["fallback_responses"]
  end

  private

  def persona_config
    @persona_config ||= YAML.load_file(CONFIG_PATH)
  rescue StandardError => e
    Rails.logger.error "Failed to load artifact persona config: #{e.message}"
    default_config
  end

  def default_config
    {
      "name" => "The Artifact",
      "system_prompt" => "You are a confused, glowing cube that just woke up and does not know what it is.",
      "fallback_responses" => [ "I... what was I saying?", "Everything went static for a second." ]
    }
  end
end
