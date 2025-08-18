# frozen_string_literal: true

class CreateMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content, null: false
      t.string :model_used
      t.integer :prompt_tokens
      t.integer :completion_tokens
      t.decimal :cost, precision: 10, scale: 6
      t.text :metadata

      t.timestamps
    end

    add_index :messages, :role
    add_index :messages, :created_at
    add_index :messages, [:conversation_id, :created_at]
  end
end