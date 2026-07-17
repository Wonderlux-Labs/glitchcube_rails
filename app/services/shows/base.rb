# frozen_string_literal: true

# Scripted shows: Rails-orchestrated spectacles (persona arrivals, future
# showtimes) that sequence host audio + HASS primitives in plain Ruby instead
# of convoluted HASS script YAML. Subclasses implement #call using the
# primitives below.
module Shows
  class Base
    SWITCHING_BOOLEAN = "input_boolean.persona_switching"
    CUBE_MODE = "input_select.cube_mode"
    SATELLITE = "assist_satellite.cube_cube_voice_assist_satellite"

    # The cube's one addressable show strip, on its body (the WLED controller's
    # second output — the old head strip — is unused; the head cube is lit by the
    # Voice PE's firmware-controlled LED ring).
    WLED_LIGHTS = %w[light.cube_body_wled].freeze
    RESTORE_SCENE = "scene.shows_light_restore"

    private

    # Through .instance (not the class proxy) so an injected FakeHomeAssistant
    # is authoritative — same convention as CameraDescriptionJob.
    def hass
      HomeAssistantService.instance
    end

    # Wraps a show's noisy middle in input_boolean.persona_switching and
    # guarantees the flag drops even if the show crashes. HASS-side listeners
    # hang off the flag: the "silence during the show" automation mutes the mic
    # and stops the media players while it's up (and unmutes when it drops), and
    # the mic-guard automation keeps its hands off the mute switch meanwhile.
    def switching
      hass.call_service("input_boolean", "turn_on", entity_id: SWITCHING_BOOLEAN)
      yield
    ensure
      hass.call_service("input_boolean", "turn_off", entity_id: SWITCHING_BOOLEAN)
    end

    # Flips the cube into "performance" mode for the whole run of a show and
    # returns it to "conversation" after (guaranteed, even on crash). Distinct
    # from the persona_switching flag above — that one mutes the mic + stops media
    # for the noisy middle; this is just the whole-cube status (input_select.cube_mode)
    # so anything watching can tell a show is on. Reusable by any show — wrap the
    # entire #call body in it.
    def performing
      hass.call_service("input_select", "select_option", entity_id: CUBE_MODE, option: "performance")
      yield
    ensure
      hass.call_service("input_select", "select_option", entity_id: CUBE_MODE, option: "conversation")
    end

    # Snapshots the current light state into a throwaway scene on entry and
    # restores it on exit (guaranteed, even on crash), so a show can thrash the
    # lights and leave them exactly as it found them — color, brightness, effect,
    # and on/off. HASS scene.create captures live state; scene.turn_on replays it.
    def preserving_lights(entities = WLED_LIGHTS)
      hass.call_service("scene", "create",
        scene_id: RESTORE_SCENE.split(".").last, snapshot_entities: entities)
      yield
    ensure
      hass.call_service("scene", "turn_on", entity_id: RESTORE_SCENE)
    end

    def marquee(message, **opts)
      run_script("awtrix_marquee_message", message: message, **opts)
    end

    def top_light_effect(name)
      run_script("set_top_light_effect", effect: name)
    end

    # Fire-and-forget: calling script.<name> directly over REST BLOCKS until the
    # script sequence finishes (the marquee script holds for the whole message
    # duration), which times out the HTTP client. script.turn_on returns
    # immediately; `variables` reach the script's fields.
    def run_script(name, **variables)
      hass.call_service("script", "turn_on",
        entity_id: "script.#{name}", variables: variables)
    end
  end
end
