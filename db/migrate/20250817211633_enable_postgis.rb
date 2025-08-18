# frozen_string_literal: true

class EnablePostgis < ActiveRecord::Migration[7.1]
  def up
    # Enable PostGIS extensions - must be the very first migration
    enable_extension 'postgis'
    enable_extension 'postgis_topology'
  end

  def down
    # Don't disable PostGIS as other migrations may depend on it
    # disable_extension 'postgis'
  end
end
