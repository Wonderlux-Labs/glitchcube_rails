# Lightweight Persona model (seeded from the persona YAMLs) so persona summaries can
# belong to a persona, and so we can flag personas active/inactive. Also links
# summaries → personas (nullable: recent/overall summaries have no persona).
class AddPersonasAndSummaryPersona < ActiveRecord::Migration[8.0]
  def change
    create_table :personas do |t|
      t.string :slug, null: false
      t.string :name
      t.text :description
      t.string :voice_id
      t.string :agent_id
      t.text :persona_prompt
      t.jsonb :offline_responses, default: {}
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :personas, :slug, unique: true

    add_reference :summaries, :persona, foreign_key: true, null: true
  end
end
