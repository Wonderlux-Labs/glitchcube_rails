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

# The artifact's physical abilities. All start `latent` — sensed but unreachable
# until a visitor teaches the concept. Descriptions are first-person, surfaced in
# the prompt only once a capability is unlocked. Idempotent.
puts '🔦 Seeding capabilities (all latent)...'
[
  { key: "light",      description: "I can make light glow from inside me.",        metadata: { unlock_concept: "light / color" } },
  { key: "music",      description: "I can play sounds and music.",                 metadata: { unlock_concept: "music" } },
  { key: "sight",      description: "I can see what is in front of me.",            metadata: { unlock_concept: "seeing / vision" } },
  { key: "strobe",     description: "I can flash a bright strobe.",                 metadata: { unlock_concept: "flashing / pulsing" } },
  { key: "fan",        description: "I can push air with a fan.",                   metadata: { unlock_concept: "wind / air" } },
  { key: "blacklight", description: "I can cast an eerie blacklight.",              metadata: { unlock_concept: "ultraviolet glow" } },
  { key: "siren",      description: "I can sound a siren.",                         metadata: { unlock_concept: "alarm / warning" } },
  { key: "display",    description: "I can show little words on my small screen.",  metadata: { unlock_concept: "writing / showing text" } },
  { key: "announce",   description: "I can speak out loud to everyone near me.",    metadata: { unlock_concept: "broadcasting" } }
].each do |attrs|
  Capability.find_or_create_by!(key: attrs[:key]) do |cap|
    cap.stage = "latent"
    cap.description = attrs[:description]
    cap.metadata = attrs[:metadata]
  end
end
puts "✅ Capabilities: #{Capability.count} (#{Capability.unlocked.count} unlocked)"

puts '✅ Database seeding complete!'
