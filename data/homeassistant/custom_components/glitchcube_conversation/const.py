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

# Conversation continuation — see _reopen_listening_after_idle in conversation.py.
# Hardcoded to the single Cube Voice satellite; revisit if we ever have more than one.
ASSIST_SATELLITE_ENTITY_ID = "assist_satellite.cube_cube_voice_assist_satellite"
CONTINUATION_CHIME_MEDIA_ID = "media-source://media_source/local/sounds/wake_word_triggered.flac"
REOPEN_LISTENING_TIMEOUT_SEC = 20
REOPEN_LISTENING_POLL_INTERVAL_SEC = 0.25