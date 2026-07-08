# app/services/prompts/configuration_loader.rb
module Prompts
  class ConfigurationLoader
    GENERAL_DIR = Rails.root.join("lib", "prompts", "general")

    def self.load_persona_config(persona_id)
      new.load_persona_config(persona_id)
    end

    # The full tool catalog (lib/prompts/tools.yml) keyed by tool slug. Loaded fresh each
    # call so edits show up without a restart during authoring.
    def self.tools_config
      path = Rails.root.join("lib", "prompts", "tools.yml")
      return {} unless File.exist?(path)

      (YAML.load_file(path) || {})["tools"] || {}
    end

    def self.persona_tools(persona_id)
      new.persona_tools(persona_id)
    end

    # Raw text of the wrapper that goes BEFORE the persona sheet.
    def self.base_system_prompt
      read_general("base_system_prompt.txt")
    end

    # Raw text of the wrapper that goes AFTER the persona sheet (tools + response format).
    def self.end_system_prompt
      read_general("end_system_prompt.txt")
    end

    def self.read_general(filename)
      path = GENERAL_DIR.join(filename)
      return nil unless File.exist?(path)

      File.read(path).strip
    end

    # Persona config comes from the DB (Persona, seeded from the YAMLs). Falls back to
    # the YAML on disk if the row isn't seeded yet, so nothing breaks pre-seed.
    def load_persona_config(persona_id)
      persona = Persona[persona_id]
      return persona.to_config_hash if persona

      load_persona_yaml(persona_id)
    rescue StandardError => e
      Rails.logger.error "Error loading persona config for #{persona_id}: #{e.message}"
      load_persona_yaml(persona_id)
    end

    # The tool slugs this persona may use. Prefers the DB config (if a `tools` field is
    # ever added there); falls back to the persona YAML, which is where they're authored today.
    def persona_tools(persona_id)
      cfg = load_persona_config(persona_id) || {}
      keys = cfg["tools"].presence || (load_persona_yaml(persona_id) || {})["tools"]
      Array(keys)
    end

    def load_persona_yaml(persona_id)
      config_path = Rails.root.join("lib", "prompts", "personas", "#{persona_id}.yml")
      return nil unless File.exist?(config_path)

      YAML.load_file(config_path)
    rescue StandardError => e
      Rails.logger.error "Error loading persona YAML for #{persona_id}: #{e.message}"
      nil
    end
  end
end
