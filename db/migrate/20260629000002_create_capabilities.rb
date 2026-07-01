class CreateCapabilities < ActiveRecord::Migration[8.0]
  def change
    create_table :capabilities do |t|
      t.string :key, null: false
      t.string :stage, null: false, default: "latent"
      t.string :artifact_name
      t.text :description
      t.jsonb :unlocked_params, null: false, default: []
      t.jsonb :vocabulary, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :capabilities, :key, unique: true
    add_index :capabilities, :stage
  end
end
