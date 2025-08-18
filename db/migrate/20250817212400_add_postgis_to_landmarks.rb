# frozen_string_literal: true

class AddPostgisToLandmarks < ActiveRecord::Migration[7.1]
  def up
    # Add spatial column for geographic point data (PostGIS already enabled in migration 000)
    add_column :landmarks, :location, :geometry

    # Add spatial index for fast proximity queries
    add_index :landmarks, :location, using: :gist

    # NOTE: Traditional indices already created in landmarks migration

    # Populate the spatial column from existing lat/lng data
    execute <<-SQL
      UPDATE landmarks#{' '}
      SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
      WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
    SQL

    # Add constraint to ensure spatial column is always populated
    add_check_constraint :landmarks,
                         'location IS NOT NULL OR (latitude IS NULL AND longitude IS NULL)',
                         name: 'landmarks_location_consistency'
  end

  def down
    remove_check_constraint :landmarks, name: 'landmarks_location_consistency'
    remove_index :landmarks, :location
    remove_column :landmarks, :location
    # PostGIS extension managed by migration 000, don't disable here
    # Traditional indices managed by landmarks migration, don't remove here
  end
end
