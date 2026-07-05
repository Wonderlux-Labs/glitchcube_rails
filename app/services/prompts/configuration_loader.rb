# app/services/prompts/configuration_loader.rb
module Prompts
  class ConfigurationLoader
    GENERAL_DIR = Rails.root.join("lib", "prompts", "general")

    def self.load_persona_config(persona_id)
      new.load_persona_config(persona_id)
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

    def load_persona_config(persona_id)
      persona_id_str = persona_id.to_s
      config_path = Rails.root.join("lib", "prompts", "personas", "#{persona_id_str}.yml")

      return nil unless File.exist?(config_path)

      begin
        YAML.load_file(config_path)
      rescue StandardError => e
        Rails.logger.error "Error loading persona config for #{persona_id}: #{e.message}"
        nil
      end
    end
  end
end
