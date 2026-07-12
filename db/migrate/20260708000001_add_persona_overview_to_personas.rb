# frozen_string_literal: true

# A short, compressed character overview (voice, running gags, tells) seeded from each
# persona YAML's `persona_overview:` key. Used by PersonaSummarizerService instead of the
# full persona_prompt so the fold can judge on-model/off-model without the whole brief.
class AddPersonaOverviewToPersonas < ActiveRecord::Migration[8.1]
  def change
    add_column :personas, :persona_overview, :text
  end
end
