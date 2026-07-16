# frozen_string_literal: true

# Sync the Persona rows from the authored YAMLs on every boot, so a persona-prompt edit
# reaches the running cube (Prompts::ConfigurationLoader reads the DB first) without anyone
# remembering to reseed. Same idempotent upsert as db/seeds.rb. Skipped in test (the suite
# manages its own personas) and quietly no-ops if the DB/table isn't there yet, so it can't
# block db:create / db:migrate on a fresh database.
unless Rails.env.test?
  Rails.application.config.after_initialize do
    Persona.sync_from_yaml! if Persona.table_exists?
  rescue StandardError => e
    Rails.logger.warn "🎭 Persona YAML sync skipped on boot: #{e.class} - #{e.message}"
  end
end
