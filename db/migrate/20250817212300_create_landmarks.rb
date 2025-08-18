# frozen_string_literal: true

class CreateLandmarks < ActiveRecord::Migration[7.1]
  def change
    create_table :landmarks do |t|
      t.string :name, null: false
      t.decimal :latitude, precision: 10, scale: 8, null: false
      t.decimal :longitude, precision: 11, scale: 8, null: false
      # t.st_point :location, geographic: true  # PostGIS point for spatial queries - add after PostGIS is enabled
      t.string :landmark_type
      t.integer :radius_meters, default: 30
      t.string :icon
      t.text :description
      t.jsonb :properties, default: {}
      t.boolean :active, default: true
      t.timestamps
    end

    add_index :landmarks, %i[latitude longitude]
    # add_index :landmarks, :location, using: :gist  # Add after PostGIS column is created
    add_index :landmarks, :landmark_type
    add_index :landmarks, :active
    add_index :landmarks, :name
  end
end
