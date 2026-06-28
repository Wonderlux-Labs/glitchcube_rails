"""Constants for the Glitch Cube Conversation integration."""

DOMAIN = "glitchcube_conversation"

# Configuration defaults
DEFAULT_HOST = "localhost"  # Fallback only - should use dynamic IP from input_text.glitchcube_host
DEFAULT_PORT = 4567
DEFAULT_API_PATH = "/api/v1/conversation"
DEFAULT_TIMEOUT = 120

# Conversation response keys
RESPONSE_KEY = "response"
ACTIONS_KEY = "actions"
CONTINUE_KEY = "continue_conversation"
MEDIA_KEY = "media_actions"

# Supported languages (can be expanded)
SUPPORTED_LANGUAGES = ["en", "en-US", "en-GB"]