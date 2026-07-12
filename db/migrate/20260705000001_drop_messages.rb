# The `messages` table is dead — the per-turn record is `ConversationLog`, and
# nothing has written a Message in the current architecture (0 rows). Dropping it.
class DropMessages < ActiveRecord::Migration[8.0]
  def up
    drop_table :messages, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "messages was dead and removed; restore from git history if ever needed"
  end
end
