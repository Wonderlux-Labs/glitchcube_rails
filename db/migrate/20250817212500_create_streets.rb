# frozen_string_literal: true

class CreateStreets < ActiveRecord::Migration[7.1]
  def change
    create_table :streets do |t|
      t.string :name, null: false
      t.string :street_type, null: false # 'radial' or 'arc'
      t.integer :width, default: 30
      t.column :geom, 'geometry(LineString, 4326)'  # PostGIS geometry column for linestrings
      t.jsonb :properties, default: {}
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :streets, :name
    add_index :streets, :street_type
    add_index :streets, :active
    add_index :streets, %i[active street_type]
    add_index :streets, :geom, using: :gist

    # Create geography index for distance calculations
    execute <<-SQL
      CREATE INDEX idx_streets_geom_geography#{' '}
      ON streets#{' '}
      USING GIST (CAST(geom AS geography));
    SQL
  end
end
