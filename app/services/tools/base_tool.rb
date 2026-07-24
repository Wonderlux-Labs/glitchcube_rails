# app/services/tools/base_tool.rb
#
# Base class for the in-Rails environment tools. Each tool exposes an OpenRouter
# tool `.definition` (what the translator LLM sees) and a `#call` that executes it
# by hitting Home Assistant directly. Almost every tool wraps a HASS script — never
# a raw device — so the script owns device routing and we only ever expose one clean
# knob per capability. Scripts MUST be fired non-blocking (script.turn_on + variables);
# the direct call_service("script", "<name>") form blocks until the sequence finishes
# and times out the HTTP client.
class Tools::BaseTool
  class << self
    # The OpenRouter::Tool definition the translator LLM sees.
    def definition
      raise NotImplementedError, "Subclasses must implement .definition"
    end

    # Execute the tool with the given (symbol-keyed) arguments.
    def call(**args)
      new.call(**args)
    end

    # Parse "R,G,B" (0-255 each) into a [r, g, b] Array, or nil if malformed.
    # Accepts an already-parsed valid Array unchanged. Shared by tools and their
    # validation blocks so the translator gets the same verdict either way.
    def parse_rgb(color)
      return color if valid_rgb?(color)
      return nil unless color.is_a?(String)

      parts = color.split(",").map { |p| Integer(p.strip, exception: false) }
      valid_rgb?(parts) ? parts : nil
    end

    def valid_rgb?(parts)
      parts.is_a?(Array) && parts.length == 3 &&
        parts.all? { |c| c.is_a?(Integer) && c.between?(0, 255) }
    end

    # Validate a 6-digit hex color string like "#FF00AA" (leading # optional).
    # Shared by tools and their validation blocks so the translator gets the same verdict.
    def valid_hex_color?(color)
      color.is_a?(String) && color.strip.match?(/\A#?[0-9a-fA-F]{6}\z/)
    end
  end

  # Instance entry point.
  def call(**args)
    raise NotImplementedError, "Subclasses must implement #call"
  end

  protected

  # Fire a HASS script non-blocking. Returns a service-call descriptor so the caller
  # can surface exactly what fired in its success_response (the visibility win).
  def run_script(script_name, **variables)
    data = { entity_id: "script.#{script_name}", variables: variables }
    HomeAssistantService.call_service("script", "turn_on", data)
    { domain: "script", service: "turn_on", data: data }
  end

  def success_response(message, data = {})
    { success: true, message: message, **data }
  end

  def error_response(message, details = {})
    { success: false, error: message, **details }
  end
end
