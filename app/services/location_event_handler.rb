# app/services/location_event_handler.rb

class LocationEventHandler
  class Error < StandardError; end

  SIGNIFICANT_LOCATIONS = {
    "temple" => {
      name: "The Temple",
      description: "Sacred space for reflection, remembrance, and letting go",
      zone_type: "spiritual",
      significance: "high"
    },
    "deep_playa" => {
      name: "Deep Playa",
      description: "Vast empty expanse beyond the city, home to large art installations and solitude",
      zone_type: "wilderness",
      significance: "high"
    },
    "center_camp" => {
      name: "Center Camp",
      description: "Hub of activity with cafe, information, and community gathering",
      zone_type: "community",
      significance: "high"
    },
    "esplanade" => {
      name: "The Esplanade",
      description: "Main thoroughfare around the city perimeter, high traffic area",
      zone_type: "transit",
      significance: "medium"
    },
    "man_base" => {
      name: "The Man",
      description: "Central focal point of Burning Man, iconic wooden figure",
      zone_type: "central",
      significance: "high"
    }
  }.freeze

  def self.handle_location_change(from_location, to_location, additional_context = {})
    new.handle_location_change(from_location, to_location, additional_context)
  end

  def self.handle_zone_transition(zone_event_type, zone_info, additional_context = {})
    new.handle_zone_transition(zone_event_type, zone_info, additional_context)
  end

  def initialize
    @speech_service = ContextualSpeechTriggerService.new
    @gps_service = Gps::GpsTrackingService.new
  end

  # Handle movement between specific locations
  def handle_location_change(from_location, to_location, additional_context = {})
    Rails.logger.info "📍 Location change detected: #{from_location} → #{to_location}"

    context = build_location_change_context(from_location, to_location, additional_context)

    # Determine if this location change is significant enough to trigger speech
    if significant_location_change?(from_location, to_location)
      Rails.logger.info "🎭 Triggering speech for significant location change"

      @speech_service.trigger_speech(
        trigger_type: "location_change",
        context: context,
        force_response: context[:force_response] || false
      )
    else
      Rails.logger.info "📍 Location change not significant enough for speech trigger"
    end
  end

  # Handle zone entry/exit events
  def handle_zone_transition(zone_event_type, zone_info, additional_context = {})
    Rails.logger.info "🌐 Zone #{zone_event_type}: #{zone_info[:zone_name] || zone_info[:zone]}"

    context = build_zone_context(zone_info, additional_context)

    # Always trigger speech for zone transitions as they're inherently significant
    @speech_service.trigger_speech(
      trigger_type: zone_event_type, # 'zone_entry' or 'zone_exit'
      context: context,
      force_response: zone_info[:force_response] || should_force_response_for_zone?(zone_info)
    )
  end

  # Handle proximity to art installations
  def handle_art_proximity(art_installation_info, additional_context = {})
    Rails.logger.info "🎨 Art proximity detected: #{art_installation_info[:art_name]}"

    context = build_art_proximity_context(art_installation_info, additional_context)

    @speech_service.trigger_speech(
      trigger_type: "art_installation_proximity",
      context: context,
      force_response: false # Art proximity is usually optional commentary
    )
  end

  # Convenience method for Deep Playa entry (as requested in the example)
  def handle_deep_playa_entry(additional_context = {})
    temple_context = additional_context[:passed_temple] ? "just passed the Temple and is" : "is"

    context = {
      zone_name: "Deep Playa",
      zone_type: "wilderness",
      zone_description: "Vast empty expanse beyond the city, home to large art installations and profound solitude",
      features: [ "Large-scale art installations", "Open space", "Fewer people", "Starry skies" ],
      entry_point: additional_context[:entry_point] || "Temple side",
      description: "You #{temple_context} now entering Deep Playa - the vast, open expanse where massive art installations stand against endless sky.",
      significance: "This transition from the bustling city to the profound emptiness of Deep Playa often triggers deep thoughts and introspection.",
      force_response: additional_context[:force_response] || false
    }.merge(additional_context)

    handle_zone_transition("zone_entry", context)
  end

  # Handle crowd density changes
  def handle_crowd_density_change(density_info, additional_context = {})
    Rails.logger.info "👥 Crowd density changed: #{density_info[:change_type]}"

    context = build_crowd_density_context(density_info, additional_context)

    # Only trigger for significant crowd changes
    if significant_crowd_change?(density_info)
      @speech_service.trigger_speech(
        trigger_type: "crowd_density_change",
        context: context,
        force_response: false
      )
    end
  end

  # Handle weather/environmental changes
  def handle_weather_change(weather_info, additional_context = {})
    Rails.logger.info "🌤️ Weather change detected: #{weather_info[:change_type]}"

    context = build_weather_context(weather_info, additional_context)

    # Trigger for significant weather changes
    if significant_weather_change?(weather_info)
      @speech_service.trigger_speech(
        trigger_type: "weather_change",
        context: context,
        force_response: weather_info[:severity] == "high"
      )
    end
  end

  private

  def build_location_change_context(from_location, to_location, additional_context)
    from_info = SIGNIFICANT_LOCATIONS[from_location.to_s.downcase] || { name: from_location.to_s.humanize }
    to_info = SIGNIFICANT_LOCATIONS[to_location.to_s.downcase] || { name: to_location.to_s.humanize }

    current_gps = get_current_gps_context

    {
      from_location: from_info[:name],
      to_location: to_info[:name],
      from_description: from_info[:description],
      to_description: to_info[:description],
      distance: additional_context[:distance],
      duration: additional_context[:duration],
      description: build_location_transition_description(from_info, to_info),
      **current_gps
    }.merge(additional_context)
  end

  def build_zone_context(zone_info, additional_context)
    zone_key = zone_info[:zone_name]&.downcase&.gsub(/\s+/, "_") || zone_info[:zone]&.downcase
    zone_details = SIGNIFICANT_LOCATIONS[zone_key] || {}

    current_gps = get_current_gps_context

    {
      zone_name: zone_info[:zone_name] || zone_info[:zone],
      zone_type: zone_details[:zone_type] || zone_info[:zone_type] || "unknown",
      zone_description: zone_details[:description] || zone_info[:description],
      features: zone_info[:features] || [],
      significance: zone_details[:significance] || "medium",
      **current_gps
    }.merge(additional_context)
  end

  def build_art_proximity_context(art_info, additional_context)
    current_gps = get_current_gps_context

    {
      art_name: art_info[:name] || art_info[:art_name],
      art_type: art_info[:type] || art_info[:art_type],
      distance: art_info[:distance] || "nearby",
      description: art_info[:description] || art_info[:art_description],
      artist: art_info[:artist],
      features: art_info[:features] || [],
      **current_gps
    }.merge(additional_context)
  end

  def build_crowd_density_context(density_info, additional_context)
    current_gps = get_current_gps_context

    {
      previous_density: density_info[:from_density] || density_info[:previous_density],
      current_density: density_info[:to_density] || density_info[:current_density],
      change_type: density_info[:change_type],
      crowd_energy: density_info[:energy_level],
      activity: density_info[:activity_type],
      crowd_type: density_info[:demographics] || density_info[:crowd_type],
      impact: describe_crowd_impact(density_info),
      **current_gps
    }.merge(additional_context)
  end

  def build_weather_context(weather_info, additional_context)
    current_gps = get_current_gps_context

    {
      previous_weather: weather_info[:from_conditions] || weather_info[:previous_weather],
      current_weather: weather_info[:to_conditions] || weather_info[:current_weather],
      temperature: weather_info[:temperature],
      wind_conditions: weather_info[:wind],
      dust_level: weather_info[:dust],
      visibility: weather_info[:visibility],
      impact_description: describe_weather_impact(weather_info),
      **current_gps
    }.merge(additional_context)
  end

  def get_current_gps_context
    return {} unless @gps_service

    begin
      gps_data = @gps_service.current_location
      return {} unless gps_data

      {
        current_coordinates: "#{gps_data[:lat]}, #{gps_data[:lng]}",
        current_address: gps_data[:address],
        weather: gps_data[:weather],
        time_of_day: Time.current.strftime("%l:%M %p"),
        temperature: gps_data[:temperature]
      }
    rescue StandardError => e
      Rails.logger.warn "⚠️ Could not get GPS context: #{e.message}"
      {}
    end
  end

  def significant_location_change?(from_location, to_location)
    from_significance = SIGNIFICANT_LOCATIONS.dig(from_location.to_s.downcase, :significance)
    to_significance = SIGNIFICANT_LOCATIONS.dig(to_location.to_s.downcase, :significance)

    # Trigger if either location is significant
    [ "high", "medium" ].include?(from_significance) || [ "high", "medium" ].include?(to_significance)
  end

  def should_force_response_for_zone?(zone_info)
    # Force response for high-significance zones
    zone_key = zone_info[:zone_name]&.downcase&.gsub(/\s+/, "_")
    significance = SIGNIFICANT_LOCATIONS.dig(zone_key, :significance)

    significance == "high" || zone_info[:force_response]
  end

  def significant_crowd_change?(density_info)
    change_type = density_info[:change_type]&.downcase

    # Significant changes worth commenting on
    [ "dramatic_increase", "dramatic_decrease", "isolated_to_crowded", "crowded_to_isolated" ].include?(change_type)
  end

  def significant_weather_change?(weather_info)
    severity = weather_info[:severity]&.downcase
    change_type = weather_info[:change_type]&.downcase

    # Significant weather changes
    [ "high", "severe" ].include?(severity) ||
    [ "dust_storm", "wind_event", "temperature_extreme", "visibility_change" ].include?(change_type)
  end

  def build_location_transition_description(from_info, to_info)
    if from_info[:description] && to_info[:description]
      "Moving from #{from_info[:description]} to #{to_info[:description]}"
    elsif to_info[:description]
      "Arriving at #{to_info[:description]}"
    else
      "Location change detected"
    end
  end

  def describe_crowd_impact(density_info)
    case density_info[:change_type]&.downcase
    when "isolated_to_crowded"
      "Sudden transition from solitude to being surrounded by people"
    when "crowded_to_isolated"
      "Peaceful transition from crowds to quieter space"
    when "dramatic_increase"
      "Significant increase in crowd density and energy"
    when "dramatic_decrease"
      "Notable decrease in crowd activity"
    else
      "Change in social environment and crowd dynamics"
    end
  end

  def describe_weather_impact(weather_info)
    case weather_info[:change_type]&.downcase
    when "dust_storm"
      "Dust storm conditions affecting visibility and comfort"
    when "wind_event"
      "Significant wind changes affecting the environment"
    when "temperature_extreme"
      "Extreme temperature conditions"
    when "visibility_change"
      "Changes in visibility affecting navigation"
    else
      "Weather conditions have shifted significantly"
    end
  end
end
