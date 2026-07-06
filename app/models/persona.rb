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

  # Hash shape matching the persona YAML, so ConfigurationLoader/SystemPromptBuilder
  # can consume it unchanged.
  def to_config_hash
    {
      "name" => name,
      "description" => description,
      "voice_id" => voice_id,
      "agent_id" => agent_id,
      "persona_prompt" => persona_prompt,
      "offline_responses" => offline_responses
    }
  end
end
