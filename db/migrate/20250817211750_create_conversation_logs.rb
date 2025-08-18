class CreateConversationLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :conversation_logs do |t|
      t.string :session_id, null: false
      t.text :user_message, null: false
      t.text :ai_response, null: false
      t.text :tool_results
      t.text :metadata

      t.timestamps
    end

    add_index :conversation_logs, :session_id
    add_index :conversation_logs, :created_at
  end
end
