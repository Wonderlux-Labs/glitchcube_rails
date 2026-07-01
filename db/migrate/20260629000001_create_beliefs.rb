class CreateBeliefs < ActiveRecord::Migration[8.0]
  def change
    create_table :beliefs do |t|
      t.text :statement, null: false
      t.string :category, null: false
      t.integer :confidence, null: false, default: 1
      t.boolean :locked, null: false, default: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :beliefs, :category
    add_index :beliefs, :confidence
    add_index :beliefs, :locked
  end
end
