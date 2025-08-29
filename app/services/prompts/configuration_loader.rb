# app/services/prompts/configuration_loader.rb
module Prompts
  class ConfigurationLoader
    def self.load_persona_config(persona_id)
      new.load_persona_config(persona_id)
    end

    def self.load_base_system_config
      new.load_base_system_config
    end

    def load_persona_config(persona_id)
      persona_id_str = persona_id.to_s
      config_path = find_config_file("personas", persona_id_str)

      return nil unless config_path

      begin
        config = YAML.load_file(config_path)
        Rails.logger.info "✅ Loaded persona config for #{persona_id_str}"
        config
      rescue StandardError => e
        Rails.logger.error "Error loading persona config for #{persona_id}: #{e.message}"
        nil
      end
    end

    def load_base_system_config
      config_path = Rails.root.join("lib", "prompts", "general", "base_system_prompt_optimized.yml")

      return nil unless File.exist?(config_path)

      begin
        config = YAML.load_file(config_path)
        Rails.logger.info "✨ Loaded optimized base system prompt"
        config
      rescue StandardError => e
        Rails.logger.error "Error loading base system prompt: #{e.message}"
        nil
      end
    end

    private

    def find_config_file(type, filename)
      optimized_path = Rails.root.join("lib", "prompts", type, "#{filename}_optimized.yml")
      original_path = Rails.root.join("lib", "prompts", type, "#{filename}.yml")

      if File.exist?(optimized_path)
        Rails.logger.info "✨ Loading optimized #{type}: #{filename}"
        optimized_path
      elsif File.exist?(original_path)
        Rails.logger.info "🎭 Loading original #{type} (will be converted): #{filename}"
        original_path
      else
        Rails.logger.warn "❌ Config not found for #{type}/#{filename}"
        nil
      end
    end
  end
end
