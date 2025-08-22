# Service Usage Examples

## Configuration

All environment variables are loaded in `config/initializers/config.rb`. Add these to your `.env` file:

```bash
# OpenRouter
OPENROUTER_API_KEY=your_api_key_here
OPENROUTER_APP_NAME=GlitchCube
OPENROUTER_SITE_URL=https://glitchcube.com

# Home Assistant  
HOME_ASSISTANT_URL=http://homeassistant.local:8123
HOME_ASSISTANT_TOKEN=your_long_lived_access_token
HOME_ASSISTANT_TIMEOUT=30
```

## OpenRouter Usage

```ruby
# Check if configured
OpenRouter.configured?

# Get a chat completion
response = OpenRouter.client.chat_completion(
  model: "anthropic/claude-3-haiku",
  messages: [
    { role: "user", content: "Hello, how are you?" }
  ]
)

# List available models
models = OpenRouter.client.models
```

## Home Assistant Usage

```ruby
# Get all entities
entities = HomeAssistantService.entities

# Get entities by domain
lights = HomeAssistantService.entities_by_domain('light')
sensors = HomeAssistantService.entities_by_domain('sensor')

# Get specific entity
entity = HomeAssistantService.entity('light.living_room')
state = HomeAssistantService.entity_state('light.living_room')

# Control entities
HomeAssistantService.turn_on('light.living_room', brightness: 255)
HomeAssistantService.turn_off('light.living_room')
HomeAssistantService.toggle('switch.fan')

# Call any service
HomeAssistantService.call_service('light', 'turn_on', {
  entity_id: 'light.living_room',
  brightness: 128,
  color_name: 'blue'
})

# Get services for a domain
light_services = HomeAssistantService.domain_services('light')

# Fire custom events
HomeAssistantService.fire_event('custom_event', { message: 'Hello' })

# Check availability
HomeAssistantService.available?

# Get history
history = HomeAssistantService.history('sensor.temperature', 1.day.ago)
```

## Error Handling

```ruby
begin
  HomeAssistantService.turn_on('light.nonexistent')
rescue HomeAssistantService::NotFoundError
  puts "Entity not found"
rescue HomeAssistantService::ConnectionError
  puts "Cannot connect to Home Assistant"
rescue HomeAssistantService::AuthenticationError
  puts "Invalid token"
end
```