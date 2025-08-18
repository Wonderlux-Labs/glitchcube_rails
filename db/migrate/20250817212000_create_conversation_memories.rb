# frozen_string_literal: true

class CreateConversationMemories < ActiveRecord::Migration[7.1]
  def change
    create_table :conversation_memories do |t|
      t.string :session_id, null: false
      t.text :summary, null: false
      t.string :memory_type, null: false
      t.integer :importance, null: false
      t.text :metadata

      t.timestamps
    end

    add_index :conversation_memories, :session_id
    add_index :conversation_memories, :memory_type
    add_index :conversation_memories, :importance
    add_index :conversation_memories, :created_at
  end
end
