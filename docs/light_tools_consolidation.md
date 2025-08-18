# Light Tools Consolidation Plan

## Overview

Simplify the current 6 light tools into 2 comprehensive tools for better usability and maintenance.

## Current Tools (6)
1. `turn_on.rb` - Turn lights on
2. `turn_off.rb` - Turn lights off  
3. `get_state.rb` - Get current light state
4. `set_color_and_brightness.rb` - Set RGB color and brightness
5. `set_effect.rb` - Set light effects
6. `list_effects.rb` - List available effects

## New Consolidated Tools (2)

### 1. Enhanced `get_state.rb` → `light.get_state`
- **Purpose**: Get comprehensive light state including all available effects
- **Key Enhancement**: Include available effects list in response
- **Tool Type**: Sync (immediate data needed)

### 2. New `set_state.rb` → `light.set_state` 
- **Purpose**: Unified control for all light operations
- **Capabilities**: on/off, brightness, color, effects, transitions
- **Tool Type**: Async (physical world changes)

## Enhanced get_state Tool

```ruby
def self.description
  "Get current state, brightness, color, and available effects of cube lights. Shows all possible effects that can be set."
end

def self.prompt_schema  
  "light.get_state(entity_id: 'light.cube_voice_ring') - Get current state and available effects"
end

# Response includes:
# - Current state (on/off)  
# - Brightness percentage
# - RGB color values
# - Current effect
# - **ALL available effects for this light** 
# - Supported color modes
# - Supported features
# - Device responsiveness status

# Custom validation with helpful messages:
validate do |params|
  errors = []
  
  if params[:entity_id] && !CUBE_LIGHT_ENTITIES.include?(params[:entity_id])
    available = CUBE_LIGHT_ENTITIES.join(", ")
    errors << "Invalid light entity '#{params[:entity_id]}'. Available cube lights: #{available}"
  end
  
  if params[:entity_id] && !light_is_responsive?(params[:entity_id])
    errors << "Light #{params[:entity_id]} is currently offline or unresponsive"
  end
  
  errors
end
```

## New set_state Tool

```ruby
def self.description
  "Unified control for cube lights: turn on/off, set brightness, color, effects, and transitions"
end

def self.prompt_schema
  "light.set_state(entity_id: 'light.cube_inner', state: 'on', brightness: 80, rgb_color: [255, 0, 0], effect: 'rainbow') - Set any combination of light properties"
end

# Parameters (all optional except entity_id):
# - entity_id: required
# - state: "on" | "off" 
# - brightness: 0-100 percentage
# - rgb_color: [r, g, b] array
# - effect: string from available effects
# - transition: seconds for smooth changes

# Advanced custom validation with helpful messages:
validate do |params|
  errors = []
  
  # 1. Entity validation with suggestions
  if params[:entity_id] && !CUBE_LIGHT_ENTITIES.include?(params[:entity_id])
    available = CUBE_LIGHT_ENTITIES.join(", ")
    errors << "Invalid light entity '#{params[:entity_id]}'. Available cube lights: #{available}"
  end
  
  # 2. RGB color validation with examples
  if params[:rgb_color]
    if !params[:rgb_color].is_a?(Array) || params[:rgb_color].length != 3
      errors << "rgb_color must be an array of 3 integers, e.g., [255, 0, 0] for red, [0, 255, 0] for green"
    elsif params[:rgb_color].any? { |c| !c.is_a?(Integer) || c < 0 || c > 255 }
      invalid = params[:rgb_color].select { |c| !c.is_a?(Integer) || c < 0 || c > 255 }
      errors << "RGB values must be integers 0-255. Invalid values: #{invalid}"
    end
  end
  
  # 3. Effect validation with live checking
  if params[:effect] && params[:entity_id]
    available_effects = get_live_effects_for(params[:entity_id])
    unless available_effects.include?(params[:effect])
      if available_effects.any?
        errors << "Effect '#{params[:effect]}' not available for #{params[:entity_id]}. Available: #{available_effects.join(', ')}"
      else
        errors << "Light #{params[:entity_id]} does not support effects"
      end
    end
  end
  
  # 4. Logical validation
  if params[:state] == 'off' && (params[:brightness] || params[:rgb_color] || params[:effect])
    errors << "Cannot set brightness, color, or effects when turning light off. Use state: 'on' instead."
  end
  
  # 5. Smart suggestions
  if params[:rgb_color] == [0, 0, 0]
    errors << "RGB [0, 0, 0] is black (no light). Did you mean to set state: 'off' instead?"
  end
  
  # 6. Brightness warnings
  if params[:brightness] && params[:brightness] < 5 && params[:state] == 'on'
    errors << "Brightness #{params[:brightness]}% is very dim. Consider 20% or higher for visibility."
  end
  
  # 7. Entity-specific logic
  if params[:entity_id] == 'light.cube_voice_ring' && params[:effect] == 'matrix'
    errors << "Voice ring doesn't support matrix effects. Try 'pulse' or 'rainbow' for voice feedback."
  end
  
  # 8. Live system check
  if params[:entity_id] && !light_is_responsive?(params[:entity_id])
    errors << "Light #{params[:entity_id]} is currently unresponsive. Check power and network connection."
  end
  
  errors
end
```

## Benefits of Consolidation

1. **Simpler Interface**: 2 tools instead of 6
2. **Better UX**: One tool to rule them all for setting
3. **Less Cognitive Load**: Easier for LLM to choose correct tool
4. **Unified Validation**: Single place for parameter validation with smart error messages
5. **Effect Discovery**: get_state shows what effects are possible
6. **Fewer Tool Calls**: Can set multiple properties in one call
7. **Enhanced Error Messages**: Helpful, actionable validation feedback
8. **Live System Awareness**: Check device responsiveness and availability
9. **Context-Aware Suggestions**: Entity-specific recommendations and warnings

## Migration Strategy

1. Enhance existing `get_state.rb` to include effects list
2. Create new `set_state.rb` with unified parameters  
3. Update Tools::Registry to register new tools
4. Remove old individual tools
5. Update personas and prompts to use new tool names
6. Test with Home Assistant integration

## Implementation Notes

- Maintain backward compatibility during transition
- Keep entity validation in BaseTool
- Preserve existing error handling patterns
- Add comprehensive parameter validation
- Include helpful examples in tool descriptions
- Log tool usage for metrics collection

Ready to implement the consolidation!