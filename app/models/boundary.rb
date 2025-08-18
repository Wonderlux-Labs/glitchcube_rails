# frozen_string_literal: true

class Boundary < ApplicationRecord
  validates :name, presence: true
  validates :boundary_type, presence: true
  validates :geom, presence: true

  scope :active, -> { where(active: true) }
  scope :by_type, ->(type) { where(boundary_type: type) }

  scope :within_viewport, lambda { |sw_lng, sw_lat, ne_lng, ne_lat|
    where("geom && ST_MakeEnvelope(?, ?, ?, ?, 4326)", sw_lng, sw_lat, ne_lng, ne_lat)
  }

  def coordinates
    return [] unless geom.present?

    result = self.class.connection.execute(
      "SELECT ST_AsGeoJSON(geom) as geojson FROM boundaries WHERE id = #{id}"
    ).first

    return [] unless result && result["geojson"]

    geojson = JSON.parse(result["geojson"])
    geojson["coordinates"] || []
  rescue StandardError
    []
  end

  def contains_point?(lat, lng)
    return false unless geom.present?

    self.class
        .where(id: id)
        .where("ST_Contains(geom, ST_SetSRID(ST_Point(?, ?), 4326))", lng.to_f, lat.to_f)
        .exists?
  rescue StandardError
    false
  end

  def self.trash_fence
    fence = by_type("fence").first
    if fence && (fence.name.blank? || fence.name.match?(/^Fence \d+$/))
      fence.update_column(:name, "Trash Fence Perimeter")
    end
    fence
  end

  def self.within_fence?(lat, lng)
    trash_fence&.contains_point?(lat, lng) || false
  end

  def self.cube_within_fence?(lat, lng)
    where(boundary_type: "fence")
      .where("ST_Contains(geom, ST_SetSRID(ST_Point(?, ?), 4326))", lng, lat)
      .exists?
  end

  def self.point_in_boundary_type?(lat, lng, boundary_type)
    where(boundary_type: boundary_type)
      .where("ST_Contains(geom, ST_SetSRID(ST_Point(?, ?), 4326))", lng, lat)
      .exists?
  end

  def self.in_city?(lat, lng)
    return true if point_in_boundary_type?(lat, lng, "city_block")

    Landmark.where(landmark_type: "plaza")
            .within_meters(lng, lat, 35)
            .exists?
  end

  def self.containing_city_block(lat, lng)
    where(boundary_type: "city_block")
      .where("ST_Contains(geom, ST_SetSRID(ST_Point(?, ?), 4326))", lng, lat)
      .first
  end

  scope :nearest, lambda { |*args|
    if args.first.is_a?(Hash)
      opts = args.first
      lng = opts[:lng] || opts[:longitude]
      lat = opts[:lat] || opts[:latitude]
      limit = opts[:limit] || 10
    else
      lng, lat, limit = args
      limit ||= 10
    end

    raise ArgumentError, "Must provide lng and lat coordinates" unless lng && lat

    point_sql = sanitize_sql_array(
      [ "ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography", lng.to_f, lat.to_f ]
    )

    active
      .select("#{table_name}.*, ST_Distance(geom::geography, #{point_sql}) AS distance_meters")
      .order(Arel.sql("geom::geography <-> #{point_sql}"))
      .limit(limit)
  }

  scope :containing_point, lambda { |lng, lat|
    raise ArgumentError, "Must provide lng and lat coordinates" unless lng && lat

    point_sql = sanitize_sql_array(
      [ "ST_SetSRID(ST_MakePoint(?, ?), 4326)", lng.to_f, lat.to_f ]
    )

    where("ST_Contains(geom, #{point_sql})")
  }

  scope :within_meters, lambda { |lng, lat, meters|
    raise ArgumentError, "Must provide lng, lat, and meters" unless lng && lat && meters

    point_sql = sanitize_sql_array(
      [ "ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography", lng.to_f, lat.to_f ]
    )

    where("ST_DWithin(geom::geography, #{point_sql}, ?)", meters.to_f)
  }

  def self.import_from_geojson(file_path, default_type = nil)
    return unless File.exist?(file_path)

    data = JSON.parse(File.read(file_path))
    imported_count = 0

    data["features"].each_with_index do |feature, index|
      props = feature["properties"] || {}

      boundary_type = props["type"] || props["boundary_type"] || default_type
      boundary_type ||= case file_path
      when /city_blocks/ then "city_block"
      when /trash_fence/ then "fence"
      else "boundary"
      end

      name = props["name"] || props["NAME"]
      if boundary_type == "city_block"
        block_id = props["FID"] || props["Id"] || index
        name ||= "City Block #{block_id}"
      end
      name ||= "#{boundary_type.humanize} #{index}"

      boundary = find_or_initialize_by(
        name: name,
        boundary_type: boundary_type
      )

      boundary.assign_attributes(
        description: props["description"] || "#{boundary_type.humanize} area",
        properties: {
          fid: feature["id"],
          original_properties: props,
          geometry_type: feature["geometry"]["type"]
        },
        active: true
      )

      if boundary.save(validate: false)
        geojson = feature["geometry"].to_json
        connection.execute(sanitize_sql_array([
                                                "UPDATE boundaries SET geom = ST_SetSRID(ST_GeomFromGeoJSON(?), 4326) WHERE id = ?",
                                                geojson, boundary.id
                                              ]))
        imported_count += 1
      else
        puts "   ❌ Failed to save boundary #{boundary.name}: #{boundary.errors.full_messages.join(', ')}"
      end
    end

    puts "✅ Imported #{imported_count} boundaries from #{File.basename(file_path)}"
    imported_count
  end

  def self.import_from_city_blocks(file_path)
    import_from_geojson(file_path, "city_block")
  end
end
