class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events do |t|
      t.string :title, null: false
      t.text :description, null: false
      t.datetime :event_time, null: false
      t.string :location
      t.integer :importance, null: false
      t.string :extracted_from_session, null: false
      t.text :metadata

      t.timestamps
    end

    add_index :events, :event_time
    add_index :events, :importance
  end
end
