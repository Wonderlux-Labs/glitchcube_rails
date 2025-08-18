# frozen_string_literal: true

class CreateBoundaries < ActiveRecord::Migration[7.1]
  def change
    create_table :boundaries do |t|
      t.string :name, null: false
      t.string :boundary_type, null: false # 'fence', 'zone', etc.
      t.text :description
      t.column :geom, 'geometry(Polygon, 4326)'  # PostGIS geometry column for polygons
      t.jsonb :properties, default: {}
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :boundaries, :name
    add_index :boundaries, :boundary_type
    add_index :boundaries, :active
    add_index :boundaries, %i[active boundary_type]
    add_index :boundaries, :geom, using: :gist

    # Create geography index for distance calculations
    execute <<-SQL
      CREATE INDEX idx_boundaries_geom_geography#{' '}
      ON boundaries#{' '}
      USING GIST (CAST(geom AS geography));
    SQL

    # GIS data will be imported via db/seeds.rb
  end
end
