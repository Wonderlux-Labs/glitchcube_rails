class CreatePeople < ActiveRecord::Migration[8.0]
  def change
    create_table :people do |t|
      t.string :name, null: false
      t.text :description, null: false
      t.string :relationship
      t.datetime :last_seen_at
      t.string :extracted_from_session, null: false
      t.text :metadata
      t.vector :embedding, limit: 1536

      t.timestamps
    end

    add_index :people, :name
    add_index :people, :last_seen_at
    add_index :people, :extracted_from_session
    add_index :people, :embedding, using: :hnsw, opclass: :vector_cosine_ops
  end
end
