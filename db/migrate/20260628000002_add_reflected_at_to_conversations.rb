class AddReflectedAtToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :reflected_at, :datetime
    add_index :conversations, :reflected_at
  end
end
