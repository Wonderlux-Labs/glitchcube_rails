class AddVectorColumnToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :embedding, :vector, limit: 1536
    add_index :events, :embedding, using: :hnsw, opclass: :vector_cosine_ops
  end
end
