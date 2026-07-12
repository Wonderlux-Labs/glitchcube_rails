# frozen_string_literal: true

# Lightweight persona record — the 8 GlitchCube subpersonalities. Seeded from the
# persona YAMLs (lib/prompts/personas/*.yml) via db/seeds.rb (find_or_create), and
# the source of truth for persona config once seeded (Prompts::ConfigurationLoader
# reads here first, falling back to YAML). Persona summaries belong to a persona.
class Persona < ApplicationRecord
  has_many :summaries, dependent: :nullify

  validates :slug, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }

  def self.[](slug)
    find_by(slug: slug.to_s)
  end

  # Upsert the Persona rows from the authored persona YAMLs (lib/prompts/personas/*.yml).
  # YAML is the authoring source; these rows are the RUNTIME source of truth
  # (Prompts::ConfigurationLoader reads the DB first), so this is the bridge that carries a
  # prompt edit into the running cube. Idempotent: config fields are refreshed from YAML
  # each run; `active` is set only on create, so a manual toggle sticks while a fresh row
  # honors the YAML's `active:` (default true). Called from db/seeds.rb AND on every boot
  # (config/initializers/sync_personas_from_yaml.rb). Returns the number of personas synced.
  def self.sync_from_yaml!
    paths = Dir[Rails.root.join("lib", "prompts", "personas", "*.yml")]
    paths.each do |path|
      slug = File.basename(path, ".yml")
      config = YAML.load_file(path) || {}
      persona = find_or_initialize_by(slug: slug)
      persona.assign_attributes(
        name: config["name"],
        description: config["description"],
        persona_overview: config["persona_overview"],
        voice_id: config["voice_id"],
        agent_id: config["agent_id"],
        persona_prompt: config["persona_prompt"],
        offline_responses: config["offline_responses"] || {}
      )
      persona.active = config.fetch("active", true) if persona.new_record? # preserve manual toggles on existing rows
      persona.save! if persona.changed? # skip the write on an unchanged row (most boots)
    end
    paths.size
  end

  # Hash shape matching the persona YAML, so ConfigurationLoader/SystemPromptBuilder
  # can consume it unchanged.
  def to_config_hash
    {
      "name" => name,
      "description" => description,
      "persona_overview" => persona_overview,
      "voice_id" => voice_id,
      "agent_id" => agent_id,
      "persona_prompt" => persona_prompt,
      "offline_responses" => offline_responses
    }
  end
end
