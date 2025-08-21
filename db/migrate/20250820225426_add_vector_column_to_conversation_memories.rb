class AddVectorColumnToConversationMemories < ActiveRecord::Migration[8.0]
  def change
    add_column :conversation_memories, :embedding, :vector,
      limit: LangchainrbRails
        .config
        .vectorsearch
        .llm
        .default_dimensions
  end
end
