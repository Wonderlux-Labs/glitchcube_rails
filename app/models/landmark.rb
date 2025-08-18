# frozen_string_literal: true

class Landmark < ApplicationRecord
  before_save :update_spatial_location

  validates :name, presence: true
  validates :latitude, presence: true, numericality: true
  validates :longitude, presence: true, numericality: true
  validates :landmark_type, presence: true

  scope :active, -> { where(active: true) }
  scope :by_type, ->(type) { where(landmark_type: type) }

  scope :within_radius, lambda { |lat, lng, radius_km|
    begin
      lat = connection.quote(lat.to_f)
      lng = connection.quote(lng.to_f)
      point = "ST_SetSRID(ST_MakePoint(#{lng}, #{lat}), 4326)"
      radius_meters = radius_km * 1000

      if connection.adapter_name.downcase.include?("postgis") ||
         connection.execute("SELECT PostGIS_version()").present?
        where("ST_DWithin(location::geography, (#{point})::geography, ?)", radius_meters)
      else
        radius_miles = radius_km * 0.621371
        where(
          "((latitude - ?) * (latitude - ?) + (longitude - ?) * (longitude - ?)) <= ?",
          lat, lat, lng, lng, (radius_miles / 69.0)**2
        )
      end
    rescue PG::UndefinedFunction, ActiveRecord::StatementInvalid
      radius_miles = radius_km * 0.621371
      where(
        "((latitude - ?) * (latitude - ?) + (longitude - ?) * (longitude - ?)) <= ?",
        lat, lat, lng, lng, (radius_miles / 69.0)**2
      )
    end
  }

  def self.the_man
    where(name: "The Man").first
  end

  def self.the_temple
    where(name: "The Temple").first
  end

  def coordinates
    [ latitude.to_f, longitude.to_f ]
  end

  def lat
    latitude.to_f
  end

  def lng
    longitude.to_f
  end

  def distance_from(lat, lng)
    if has_spatial_data?
      sql = "SELECT ST_Distance(location::geography, ST_Point(?, ?)::geography) as distance
             FROM landmarks WHERE id = ?"
      result = self.class.connection.select_one(
        self.class.sanitize_sql([ sql, lng.to_f, lat.to_f, id ])
      )
      result["distance"].to_f / 1609.34
    else
      require "geocoder"
      require "geocoder/calculations"
      Geocoder.configure(units: :mi) unless Geocoder.config.units
      Geocoder::Calculations.distance_between([ lat, lng ], coordinates, units: :mi)
    end
  rescue StandardError
    require "geocoder"
    require "geocoder/calculations"
    Geocoder.configure(units: :mi) unless Geocoder.config.units
    Geocoder::Calculations.distance_between([ lat, lng ], coordinates, units: :mi)
  end

  def within_radius?(lat, lng, radius_miles = nil)
    radius_miles ||= (radius_meters || 30) / 1609.34
    distance_from(lat, lng) <= radius_miles
  end

  def spatial_data?
    respond_to?(:location) && location.present? &&
      self.class.connection.adapter_name.downcase.include?("postgis")
  rescue StandardError
    false
  end

  def self.near_location(lat, lng, radius_miles = 0.1)
    radius_km = radius_miles * 1.609344
    within_radius(lat, lng, radius_km).active
  end

  def self.center_camp
    where(name: "Center Camp", landmark_type: "gathering").first ||
      where(name: "Center Camp").first
  end

  def self.the_man
    where(name: "The Man", landmark_type: "center").first ||
      where(name: "The Man").first
  end

  def self.the_temple
    where(name: "The Temple", landmark_type: "sacred").first ||
      where(name: "The Temple").first
  end

  def self.by_distance_from(lat, lng)
    if postgis_available?
      lat_safe = connection.quote(lat.to_f)
      lng_safe = connection.quote(lng.to_f)
      point = "ST_SetSRID(ST_MakePoint(#{lng_safe}, #{lat_safe}), 4326)"
      active.order(
        Arel.sql("ST_Distance(location::geography, (#{point})::geography)")
      )
    else
      active.sort_by { |landmark| landmark.distance_from(lat, lng) }
    end
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

    if postgis_available? && column_names.include?("location")
      point_sql = sanitize_sql_array(
        [ "ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography", lng.to_f, lat.to_f ]
      )

      active
        .select("#{table_name}.*, ST_Distance(#{table_name}.location::geography, #{point_sql}) AS distance_meters")
        .order(Arel.sql("#{table_name}.location::geography <-> #{point_sql}"))
        .limit(limit)
    else
      by_distance_from(lat, lng).limit(limit)
    end
  }

  scope :within_meters, lambda { |lng, lat, meters|
    raise ArgumentError, "Must provide lng, lat, and meters" unless lng && lat && meters

    if postgis_available? && column_names.include?("location")
      point_sql = sanitize_sql_array(
        [ "ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography", lng.to_f, lat.to_f ]
      )

      where("ST_DWithin(#{table_name}.location::geography, #{point_sql}, ?)", meters.to_f)
    else
      radius_miles = meters.to_f / 1609.34
      near_location(lat, lng, radius_miles)
    end
  }

  scope :within_bounds, lambda { |sw_lng, sw_lat, ne_lng, ne_lat|
    if postgis_available? && column_names.include?("location")
      box = "POLYGON((#{sw_lng} #{sw_lat}, #{sw_lng} #{ne_lat}, #{ne_lng} #{ne_lat}, #{ne_lng} #{sw_lat}, #{sw_lng} #{sw_lat}))"
      where("ST_Within(location, ST_GeomFromText('SRID=4326;#{box}'))")
    else
      where(latitude: sw_lat..ne_lat, longitude: sw_lng..ne_lng)
    end
  }

  def self.postgis_available?
    @postgis_available ||= begin
      connection.execute("SELECT PostGIS_version()").present?
    rescue StandardError
      false
    end
  end

  def self.import_from_gis_data(gis_data_path = "data/gis")
    import_from_landmarks_json(File.join(gis_data_path, "burning_man_landmarks.json"))
    import_from_toilets_geojson(File.join(gis_data_path, "toilets.geojson"))
    import_from_plazas_geojson(File.join(gis_data_path, "plazas.geojson"))
    import_from_cpns_geojson(File.join(gis_data_path, "cpns.geojson"))

    Street.import_from_geojson(File.join(gis_data_path, "street_lines.geojson")) if defined?(Street)

    return unless defined?(Boundary)

    Boundary.import_from_geojson(File.join(gis_data_path, "city_blocks.geojson"), "city_block")
    Boundary.import_from_geojson(File.join(gis_data_path, "trash_fence.geojson"), "fence")
  end

  private

  def self.import_from_landmarks_json(file_path)
    return unless File.exist?(file_path)

    data = JSON.parse(File.read(file_path))
    data["landmarks"].each do |landmark_data|
      landmark = find_or_initialize_by(
        name: landmark_data["name"],
        landmark_type: landmark_data["type"]
      )

      landmark.assign_attributes(
        latitude: landmark_data["lat"],
        longitude: landmark_data["lng"],
        icon: landmark_data["icon"],
        radius_meters: landmark_data["radius"] || 30,
        description: landmark_data["context"],
        properties: {
          alias: landmark_data["alias"],
          cpn_type: landmark_data["cpn_type"]
        }.compact,
        active: true
      )

      landmark.save! if landmark.changed?
    end
  end

  def self.import_from_toilets_geojson(file_path)
    return unless File.exist?(file_path)

    data = JSON.parse(File.read(file_path))
    data["features"].each_with_index do |feature, index|
      coordinates = feature["geometry"]["coordinates"][0]
      centroid = calculate_polygon_centroid(coordinates)

      landmark = find_or_initialize_by(
        name: "Toilet #{index + 1}",
        landmark_type: "toilet"
      )

      landmark.assign_attributes(
        latitude: centroid[1],
        longitude: centroid[0],
        icon: "🚻",
        radius_meters: 20,
        description: "Portable toilet facility",
        properties: {
          fid: feature["id"],
          ref: feature["properties"]["ref"]
        },
        active: true
      )

      landmark.save! if landmark.changed?
    end
  end

  def self.import_from_plazas_geojson(file_path)
    return unless File.exist?(file_path)

    data = JSON.parse(File.read(file_path))
    data["features"].each do |feature|
      coordinates = feature["geometry"]["coordinates"][0]
      centroid = calculate_polygon_centroid(coordinates)

      landmark = find_or_initialize_by(
        name: feature["properties"]["Name"],
        landmark_type: "plaza"
      )

      landmark.assign_attributes(
        latitude: centroid[1],
        longitude: centroid[0],
        icon: "🏛️",
        radius_meters: 50,
        description: "Community plaza and gathering space",
        properties: {
          fid: feature["id"]
        },
        active: true
      )

      landmark.save! if landmark.changed?
    end
  end

  def self.import_from_cpns_geojson(file_path)
    return unless File.exist?(file_path)

    data = JSON.parse(File.read(file_path))
    data["features"].each do |feature|
      name = feature["properties"]["NAME"]
      cpn_type = feature["properties"]["TYPE"] || "CPN"

      landmark = find_or_initialize_by(
        name: name,
        landmark_type: "cpn"
      )

      landmark.assign_attributes(
        latitude: feature["geometry"]["coordinates"][1],
        longitude: feature["geometry"]["coordinates"][0],
        icon: "📍",
        radius_meters: 30,
        description: "Center Placement: #{name}",
        properties: {
          fid: feature["id"],
          cpn_type: cpn_type,
          alias: feature["properties"]["ALIAS1"]
        }.compact,
        active: true
      )

      landmark.save! if landmark.changed?
    end
  end

  def self.calculate_polygon_centroid(coordinates)
    lat_sum = coordinates.sum { |coord| coord[1] }
    lng_sum = coordinates.sum { |coord| coord[0] }
    count = coordinates.length

    [ lng_sum / count, lat_sum / count ]
  end

  private_class_method :import_from_landmarks_json, :import_from_toilets_geojson,
                       :import_from_plazas_geojson, :import_from_cpns_geojson,
                       :calculate_polygon_centroid

  def update_spatial_location
    return unless latitude.present? && longitude.present?
    return unless respond_to?(:location=)

    begin
      if self.class.postgis_available?
        self.location = "SRID=4326;POINT(#{longitude} #{latitude})"
      end
    rescue StandardError => e
      Rails.logger&.warn("Failed to update spatial location: #{e.message}")
    end
  end

  def has_spatial_data?
    spatial_data?
  end
end
