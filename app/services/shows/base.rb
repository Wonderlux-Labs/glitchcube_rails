# frozen_string_literal: true

# Scripted shows: Rails-orchestrated spectacles (persona arrivals, future
# showtimes) that sequence host audio + HASS primitives in plain Ruby instead
# of convoluted HASS script YAML. Subclasses implement #call using the
# primitives below.
module Shows
  class Base
    SWITCHING_BOOLEAN = "input_boolean.persona_switching"
    SATELLITE = "assist_satellite.cube_cube_voice_assist_satellite"

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

    def marquee(message, **opts)
      run_script("awtrix_marquee_message", message: message, **opts)
    end

    def light_effect(name)
      run_script("set_cube_light_effect", effect: name)
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
