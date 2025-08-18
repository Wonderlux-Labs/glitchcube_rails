# app/services/tools/modes/mode_control.rb
class Tools::Modes::ModeControl < Tools::BaseTool
  def self.description
    "Put the Cube temporarily into special operational modes"
  end

  def self.narrative_desc
    "control modes - change operational modes and special states"
  end

  def self.prompt_schema
    "mode_control(mode: 'emergency_mode', action: 'activate') - Control Cube operational modes"
  end

  def self.tool_type
    :async # Mode changes happen after response
  end

  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "mode_control"
      description "Control special operational modes of the Cube (emergency, stealth, theme song)"

      parameters do
        string :mode, required: true,
               description: "Mode to control",
               enum: -> { Tools::Modes::ModeControl.available_modes }

        string :action, required: true,
               description: "Action to perform",
               enum: [ "activate", "deactivate", "toggle" ]
      end
    end
  end

  def self.available_modes
    [ "emergency_mode", "stealth_mode", "play_theme_song" ]
  end

  def call(mode:, action:)
    # Map modes to their corresponding entities
    # Some are input_booleans, some might be input_selects or switches
    mode_entities = {
      "emergency_mode" => { type: "input_boolean", entity_id: "input_boolean.emergency_mode" },
      "stealth_mode" => { type: "input_boolean", entity_id: "input_boolean.stealth_mode" },
      "play_theme_song" => { type: "switch", entity_id: "switch.play_theme_song" }
    }

    mode_config = mode_entities[mode]
    unless mode_config
      return error_response(
        "Unknown mode: #{mode}",
        available_modes: available_modes
      )
    end

    # Map actions to Home Assistant services
    service_map = {
      "activate" => "turn_on",
      "deactivate" => "turn_off",
      "toggle" => "toggle"
    }

    service = service_map[action]
    unless service
      return error_response(
        "Invalid action: #{action}",
        available_actions: service_map.keys
      )
    end

    # Call Home Assistant service
    begin
      result = HomeAssistantService.call_service(
        mode_config[:type],
        service,
        { entity_id: mode_config[:entity_id] }
      )

      action_past_tense = action == "activate" ? "activated" : (action == "deactivate" ? "deactivated" : "toggled")

      success_response(
        "#{action_past_tense.capitalize} #{mode.humanize}",
        mode: mode,
        action: action,
        entity_type: mode_config[:type],
        entity_id: mode_config[:entity_id],
        service_result: result
      )
    rescue HomeAssistantService::Error => e
      error_response("Failed to control #{mode}: #{e.message}")
    end
  end
end
