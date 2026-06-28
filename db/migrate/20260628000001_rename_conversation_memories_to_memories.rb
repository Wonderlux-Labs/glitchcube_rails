class RenameConversationMemoriesToMemories < ActiveRecord::Migration[8.0]
  def change
    rename_table :conversation_memories, :memories

    rename_column :memories, :summary, :content
    rename_column :memories, :memory_type, :category

    # Memories are no longer tied to a conversation session — the reflection job
    # creates them with no session provenance.
    remove_column :memories, :session_id, :string

    add_column :memories, :emotion, :string
    add_column :memories, :occurs_at, :datetime
    add_index :memories, :occurs_at
  end
end
