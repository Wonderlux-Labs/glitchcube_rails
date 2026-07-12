class DropEventPersonFactTables < ActiveRecord::Migration[8.0]
  def up
    drop_table :events
    drop_table :people
    drop_table :facts
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
