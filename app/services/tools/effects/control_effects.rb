# app/services/tools/effects/control_effects.rb
class Tools::Effects::ControlEffects < Tools::BaseTool
  def self.description
    "Control brief environmental effects like fan, strobe, blacklight, and siren with auto-toggle"
  end

  def self.narrative_desc
    "control effects - manage your stage effects - you have a strobe, a giant fan (perfect for bribing hot burners or trolling htem with a duststorm), a strobe, a siren, blacklights and......a toastER?!"
  end

  def self.prompt_schema
    "control_effects(effect: 'fan', action: 'on') - Control environmental effects"
  end

  def self.tool_type
    :async # Effect control happens after response
  end

  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "control_effects"
      description "Control brief environmental effects like fan, strobe lighting, blacklight, and siren (all auto-toggle off)"

      parameters do
        string :effect, required: true,
               description: "Effect to control",
               enum: -> { Tools::Effects::ControlEffects.available_effects }

        string :action, required: true,
               description: "Action to perform (on/off/toggle)",
               enum: [ "on", "off", "toggle" ]
      end
    end
  end

  def self.available_effects
    [ "fan", "strobe", "blacklight", "siren" ]
  end

  def call(effect:, action:)
    # Check fan cooldown before allowing fan operation
    if effect == "fan" && action == "on"
      begin
        cooldown_state = HomeAssistantService.get_entity_state("input_boolean.fan_cooldown")
        if cooldown_state&.dig("state") == "on"
          return error_response(
            "Fan is in cooldown mode (power hungry - 1 hour block after use)",
            cooldown_remaining: "Check fan cooldown status"
          )
        end
      rescue => e
        Rails.logger.warn "Could not check fan cooldown: #{e.message}"
      end
    end

    # Map effects to their corresponding entities (power switches preferred)
    effect_entities = {
      "fan" => "switch.fan_switch",         # Direct power switch
      "strobe" => "switch.strobe_switch",   # Direct power switch
      "blacklight" => "switch.blacklight_switch", # Direct power switch
      "siren" => "siren.small_siren"       # Direct siren entity
    }

    entity_id = effect_entities[effect]
    unless entity_id
      return error_response(
        "Unknown effect: #{effect}",
        available_effects: available_effects
      )
    end

    # Map actions to Home Assistant services
    service_map = {
      "on" => "turn_on",
      "off" => "turn_off",
      "toggle" => "toggle"
    }

    service = service_map[action]
    unless service
      return error_response(
        "Invalid action: #{action}",
        available_actions: service_map.keys
      )
    end

    # Call Home Assistant service (determine domain from entity_id)
    begin
      domain = entity_id.split(".").first
      result = HomeAssistantService.call_service(
        domain,
        service,
        { entity_id: entity_id }
      )

      success_response(
        "#{action.capitalize}ed #{effect} effect",
        effect: effect,
        action: action,
        entity_id: entity_id,
        service_result: result
      )
    rescue HomeAssistantService::Error => e
      error_response("Failed to control #{effect}: #{e.message}")
    end
  end
end
