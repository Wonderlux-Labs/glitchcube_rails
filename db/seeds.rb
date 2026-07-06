# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# GIS / location seeding is DISABLED for this iteration.
# Importing Black Rock City geography (streets/landmarks/boundaries) requires
# PostGIS, which has been intentionally removed from the database layer. The
# location/GPS Ruby code is kept as unused reference; the streets/landmarks/
# boundaries tables exist but stay empty. Restore this block (and PostGIS)
# when re-enabling GPS for a Burning Man deployment.
puts '⏭️  GIS/location seeding disabled (PostGIS not installed this iteration)'

# Personas — seeded from the persona YAMLs (lib/prompts/personas/*.yml). Idempotent:
# config fields are refreshed from the YAML each run, but a manually-toggled `active`
# flag on an existing row is preserved (we only default active: true on create).
persona_files = Dir[Rails.root.join('lib', 'prompts', 'personas', '*.yml')]
persona_files.each do |path|
  slug = File.basename(path, '.yml')
  config = YAML.load_file(path) || {}
  persona = Persona.find_or_initialize_by(slug: slug)
  persona.assign_attributes(
    name: config['name'],
    description: config['description'],
    voice_id: config['voice_id'],
    agent_id: config['agent_id'],
    persona_prompt: config['persona_prompt'],
    offline_responses: config['offline_responses'] || {}
  )
  persona.active = true if persona.new_record? # preserve manual active toggles on existing rows
  persona.save!
end
puts "✅ Seeded #{persona_files.size} personas (#{Persona.active.count} active)"

puts '✅ Database seeding complete!'
