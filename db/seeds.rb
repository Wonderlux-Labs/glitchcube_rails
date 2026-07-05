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

puts '✅ Database seeding complete!'
