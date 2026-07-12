# frozen_string_literal: true

# The amnesia-cube self-model (evolving character sheet + beliefs + capabilities)
# is gone; GlitchCube is back to a roster of static personas. Drop its tables.
class DropAmnesiaSelfModel < ActiveRecord::Migration[8.0]
  def up
    drop_table :beliefs, if_exists: true
    drop_table :capabilities, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
