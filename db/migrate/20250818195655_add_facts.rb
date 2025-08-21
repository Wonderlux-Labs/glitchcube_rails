class AddFacts < ActiveRecord::Migration[8.0]
  def change
    create_table :facts do |t|
      t.string :heard_it_from?
      t.text :text, null: false
      t.text :metadata
      t.timestamps
    end
  end
end
