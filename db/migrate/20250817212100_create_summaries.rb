# frozen_string_literal: true

class CreateSummaries < ActiveRecord::Migration[7.1]
  def change
    create_table :summaries do |t|
      t.text :summary_text, null: false
      t.string :summary_type, null: false
      t.integer :message_count, null: false
      t.datetime :start_time
      t.datetime :end_time
      t.text :metadata

      t.timestamps
    end

    add_index :summaries, :summary_type
    add_index :summaries, :start_time
    add_index :summaries, :end_time
  end
end