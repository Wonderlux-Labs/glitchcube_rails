# Consolidated Alert System Guide

## Overview

The Consolidated Alert System provides a centralized approach to health monitoring and alerting for your Glitch Cube installation. Instead of having separate notification systems for each health check, all alerts are consolidated into a single sensor with comprehensive attributes.

## Key Components

### 1. Consolidated Alert Template Sensor
**Entity:** `sensor.glitch_cube_consolidated_alerts`

**State Values:**
- `on` - One or more alerts are active
- `off` - All systems healthy

**Key Attributes:**
- `alert_count` - Number of active alerts
- `active_alerts` - List of all active alerts with details
- `critical_alerts` - List of critical alerts only
- `warning_alerts` - List of warning alerts only
- `summary` - Human-readable summary (e.g., "3 active alerts")

### 2. Monitored Health Checks

| Health Check | Trigger Condition | Alert Type | Icon |
|--------------|------------------|------------|------|
| **App Health** | `sensor.glitch_cube_app_health` == 'offline' | Critical | `mdi:application-off` |
| **Internet Connectivity** | `sensor.internet_connectivity` == 'disconnected' | Warning | `mdi:wifi-off` |
| **API Health** | `sensor.glitchcube_api_health` in ['unhealthy', 'unavailable'] | Critical | `mdi:api-off` |
| **Error Rate** | `sensor.glitchcube_error_rate` > 50% | Warning | `mdi:alert-circle` |
| **Battery Level** | `sensor.glitchcube_battery` < 20% | Warning | `mdi:battery-low` |
| **System Temperature** | `sensor.macmini_composite_temperature` > 180°F | Critical | `mdi:thermometer-alert` |

### 3. Automated Notifications

The system includes three automation components:

#### Primary Alert Notification
- **Trigger:** When consolidated sensor goes from 'off' to 'on'
- **Action:** Creates persistent notification with all active alerts
- **Notification ID:** `glitch_cube_consolidated_alerts`

#### Alert Cleared Notification
- **Trigger:** When consolidated sensor goes from 'on' to 'off'  
- **Action:** Clears the persistent notification

#### Alert Update Notification
- **Trigger:** When active alerts change while sensor is 'on'
- **Action:** Updates persistent notification with current alert status

## Usage Examples

### Dashboard Integration
```yaml
type: entity
entity: sensor.glitch_cube_consolidated_alerts
name: System Health
icon: mdi:shield-check
state_color: true
```

### Conditional Card (Show only when alerts active)
```yaml
type: conditional
conditions:
  - entity: sensor.glitch_cube_consolidated_alerts
    state: "on"
card:
  type: entities
  title: "🚨 Active Alerts"
  entities:
    - entity: sensor.glitch_cube_consolidated_alerts
      type: attribute
      attribute: summary
    - entity: sensor.glitch_cube_consolidated_alerts
      type: attribute
      attribute: alert_count
```

### Automation Examples

#### Emergency Actions on Critical Alerts
```yaml
- id: emergency_critical_alert_response
  alias: "Emergency Response to Critical Alerts"
  trigger:
    - platform: template
      value_template: >
        {{ state_attr('sensor.glitch_cube_consolidated_alerts', 'critical_alerts') | length > 0 }}
  action:
    - service: script.turn_on
      target:
        entity_id: script.emergency_shutdown
    - service: notify.mobile_app
      data:
        title: "CRITICAL: Glitch Cube Emergency"
        message: "Critical system alerts detected - emergency protocols activated"
```

#### Daily Health Summary
```yaml
- id: daily_health_summary
  alias: "Daily Health Summary"
  trigger:
    - platform: time
      at: "08:00:00"
  action:
    - service: notify.persistent_notification
      data:
        title: "Daily Health Report"
        message: >
          **System Status:** {{ state_attr('sensor.glitch_cube_consolidated_alerts', 'summary') }}
          
          {% if is_state('sensor.glitch_cube_consolidated_alerts', 'on') %}
          **Active Issues:**
          {% for alert in state_attr('sensor.glitch_cube_consolidated_alerts', 'active_alerts') %}
          • {{ alert.title }}: {{ alert.message }}
          {% endfor %}
          {% endif %}
```

### Template Examples

#### Get Alert Count
```jinja2
{{ state_attr('sensor.glitch_cube_consolidated_alerts', 'alert_count') | int(0) }}
```

#### Check for Specific Alert Type
```jinja2
{% set critical_count = state_attr('sensor.glitch_cube_consolidated_alerts', 'critical_alerts') | length %}
{{ 'CRITICAL ALERTS ACTIVE' if critical_count > 0 else 'No Critical Alerts' }}
```

#### List All Active Alert Titles
```jinja2
{% for alert in state_attr('sensor.glitch_cube_consolidated_alerts', 'active_alerts') %}
  {{ alert.title }}{% if not loop.last %}, {% endif %}
{% endfor %}
```

## Alert Data Structure

Each alert in the `active_alerts` attribute contains:
```json
{
  "id": "app_health",
  "type": "critical",
  "title": "App Offline", 
  "message": "Glitch Cube app has been offline",
  "entity": "sensor.glitch_cube_app_health",
  "since": "14:30:25",
  "icon": "mdi:application-off"
}
```

## Customization

### Adding New Health Checks
To add a new health check, modify the template sensor in `/config/homeassistant/template/consolidated_alerts.yaml`:

1. Add condition check in the `state` template
2. Add corresponding entry in `active_alerts` attribute  
3. Update `alert_count` calculation
4. Consider the appropriate alert type (critical vs warning)

### Modifying Thresholds
Current thresholds can be adjusted in the template:
- **Error Rate:** Currently 50% (line 52)
- **Battery Level:** Currently 20% (line 65)
- **Temperature:** Currently 180°F (line 78)

### Custom Alert Types
The system supports any alert type in the `type` field. Current types:
- `critical` - For system-threatening issues
- `warning` - For issues that need attention but aren't critical

## Troubleshooting

### Sensor Not Updating
- Check that all referenced sensor entities exist
- Verify template syntax in Developer Tools > Template
- Ensure the template file is being included in configuration.yaml

### Missing Alerts
- Confirm the triggering sensor states match expected values
- Check template conditions with current sensor states
- Verify the alert appears in `active_alerts` attribute

### Persistent Notifications Not Appearing
- Check automation traces in Developer Tools > Automations
- Verify notification service is working with a test message
- Ensure `notification_id` is unique across your system

## Best Practices

1. **Monitor regularly** - Check the consolidated sensor daily
2. **Test conditions** - Verify your critical thresholds are appropriate
3. **Customize messaging** - Adapt alert messages to your specific context
4. **Regular maintenance** - Review and update health checks as your system evolves
5. **Documentation** - Keep this guide updated when making changes

## Integration with Existing Systems

The consolidated system is designed to work alongside your existing health monitoring:
- Individual health sensors continue to operate independently
- Original alert automations have been updated to complement (not duplicate) the consolidated system
- Logbook entries are still created for historical tracking
- Emergency response scripts can still be triggered independently