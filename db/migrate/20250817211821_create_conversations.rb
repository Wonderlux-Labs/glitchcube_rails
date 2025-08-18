class CreateConversations < ActiveRecord::Migration[8.0]
  def change
    create_table :conversations do |t|
      t.string :session_id, null: false
      t.string :persona
      t.string :source, default: 'api'
      t.datetime :started_at
      t.datetime :ended_at
      t.string :end_reason
      t.integer :message_count, default: 0
      t.decimal :total_cost, precision: 10, scale: 6, default: 0.0
      t.integer :total_tokens, default: 0
      t.boolean :continue_conversation, default: true
      t.text :flow_data
      t.text :metadata

      t.timestamps
    end

    add_index :conversations, :session_id, unique: true
    add_index :conversations, :started_at
    add_index :conversations, :ended_at
    add_index :conversations, :persona
  end
end
