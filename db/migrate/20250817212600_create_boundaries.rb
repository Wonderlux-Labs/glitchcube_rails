# frozen_string_literal: true

class CreateBoundaries < ActiveRecord::Migration[7.1]
  def change
    create_table :boundaries do |t|
      t.string :name, null: false
      t.string :boundary_type, null: false # 'fence', 'zone', etc.
      t.text :description
      t.jsonb :properties, default: {}
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :boundaries, :name
    add_index :boundaries, :boundary_type
    add_index :boundaries, :active
    add_index :boundaries, %i[active boundary_type]
  end
end
