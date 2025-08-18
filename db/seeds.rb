# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts '🌱 Seeding GIS database...'

# Import GIS data
gis_data_path = Rails.root.join('data', 'gis')

if Dir.exist?(gis_data_path) && Landmark.count < 150
  puts 'Importing GIS data...'

  # Import landmarks from various sources
  landmarks_file = gis_data_path.join('burning_man_landmarks.json')
  if File.exist?(landmarks_file)
    puts '  Importing landmarks...'
    Landmark.send(:import_from_landmarks_json, landmarks_file.to_s)
  end

  toilets_file = gis_data_path.join('toilets.geojson')
  if File.exist?(toilets_file)
    puts '  Importing toilets...'
    Landmark.send(:import_from_toilets_geojson, toilets_file.to_s)
  end

  plazas_file = gis_data_path.join('plazas.geojson')
  if File.exist?(plazas_file)
    puts '  Importing plazas...'
    Landmark.send(:import_from_plazas_geojson, plazas_file.to_s)
  end

  cpns_file = gis_data_path.join('cpns.geojson')
  if File.exist?(cpns_file)
    puts '  Importing CPNs...'
    Landmark.send(:import_from_cpns_geojson, cpns_file.to_s)
  end

  # Import streets
  streets_file = gis_data_path.join('street_lines.geojson')
  if File.exist?(streets_file)
    puts '  Importing streets...'
    Street.import_from_geojson(streets_file.to_s)
  end

  # Import boundaries
  city_blocks_file = gis_data_path.join('city_blocks.geojson')
  if File.exist?(city_blocks_file)
    puts '  Importing city blocks...'
    Boundary.import_from_geojson(city_blocks_file.to_s, 'city_block')
  end

  trash_fence_file = gis_data_path.join('trash_fence.geojson')
  if File.exist?(trash_fence_file)
    puts '  Importing trash fence...'
    Boundary.import_from_geojson(trash_fence_file.to_s, 'fence')
  end

  # Report what was imported
  landmark_count = Landmark.count
  street_count = Street.count
  boundary_count = Boundary.count

  puts "✅ GIS import complete: #{landmark_count} landmarks, #{street_count} streets, #{boundary_count} boundaries"
else
  puts '⚠️  GIS data directory not found at data/gis - skipping GIS import'
end

puts '✅ Database seeding complete!'
