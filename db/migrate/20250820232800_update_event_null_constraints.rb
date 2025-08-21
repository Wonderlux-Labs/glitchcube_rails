class UpdateEventNullConstraints < ActiveRecord::Migration[8.0]
  def change
    # Set default value for title and keep it as required field
    change_column :events, :title, :string, null: false, default: "Event"

    # Remove null constraints from other fields
    change_column :events, :description, :text, null: true
    change_column :events, :event_time, :datetime, null: true
    change_column :events, :importance, :integer, null: true
    change_column :events, :extracted_from_session, :string, null: true
  end
end
