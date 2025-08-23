"""Glitch Cube Conversation Agent."""
from __future__ import annotations

import aiohttp
import asyncio
import logging
from typing import Any
import os
from pathlib import Path

from homeassistant.components import conversation
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers import intent
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.util import dt as dt_util

from .const import (
    DOMAIN,
    DEFAULT_HOST,
    DEFAULT_PORT,
    DEFAULT_TIMEOUT,
    RESPONSE_KEY,
    ACTIONS_KEY,
    CONTINUE_KEY,
    MEDIA_KEY,
    SUPPORTED_LANGUAGES,
)

_LOGGER = logging.getLogger(__name__)

# Set up dedicated file logging for conversation agent
def setup_conversation_logger():
    """Set up a dedicated logger for the conversation agent."""
    # Create logs directory if it doesn't exist
    log_dir = Path("/config/logs")
    log_dir.mkdir(exist_ok=True)
    
    # Create a file handler for conversation logs
    file_handler = logging.FileHandler(log_dir / "glitchcube_conversation.log")
    file_handler.setLevel(logging.DEBUG)
    
    # Create formatter
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    file_handler.setFormatter(formatter)
    
    # Add handler to logger
    _LOGGER.addHandler(file_handler)
    _LOGGER.setLevel(logging.DEBUG)
    
    return _LOGGER

# Initialize the dedicated logger
_LOGGER = setup_conversation_logger()


async def async_setup_entry(
    hass: HomeAssistant,
    config_entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up Glitch Cube conversation entity."""
    entity = GlitchCubeConversationEntity(config_entry)
    async_add_entities([entity])


class GlitchCubeConversationEntity(conversation.ConversationEntity):
    """Glitch Cube conversation agent."""

    def __init__(self, config_entry: ConfigEntry) -> None:
        """Initialize the conversation entity."""
        self._config_entry = config_entry
        # Get connection details from config
        # If host is empty or missing, we'll use dynamic host from input_text
        host = config_entry.data.get("host", "")
        port = config_entry.data.get("port", DEFAULT_PORT)
        
        # If no host specified, we'll determine it dynamically
        if not host:
            self._attr_name = f"Glitch Cube (Dynamic IP:{port})"
            # Don't set a fixed URL - we'll get it dynamically
            self._api_url = None
        else:
            self._attr_name = f"Glitch Cube ({host}:{port})"
            self._api_url = f"http://{host}:{port}/api/v1/conversation"
        
        self._attr_unique_id = f"{DOMAIN}_{config_entry.entry_id}"
        self._timeout = DEFAULT_TIMEOUT  # Optimized for voice interactions
        
        _LOGGER.info("Initialized Glitch Cube conversation agent: %s", 
                     self._api_url if self._api_url else "Dynamic IP mode")

    @property
    def supported_languages(self) -> list[str]:
        """Return list of supported languages."""
        return SUPPORTED_LANGUAGES

    def _get_current_api_url(self) -> str:
        """Get the current API URL, checking for dynamic host first."""
        # Always check for dynamic host first (for dynamic IP support)
        try:
            glitchcube_host_state = self.hass.states.get("input_text.glitchcube_host")
            if (glitchcube_host_state and 
                glitchcube_host_state.state and 
                glitchcube_host_state.state not in ["unknown", "unavailable", ""]):
                
                dynamic_host = glitchcube_host_state.state.strip()
                port = self._config_entry.data.get("port", DEFAULT_PORT)
                api_url = f"http://{dynamic_host}:{port}/api/v1/conversation"
                _LOGGER.debug(f"Using dynamic host from input_text: {dynamic_host}")
                return api_url
            else:
                state_value = glitchcube_host_state.state if glitchcube_host_state else "None"
                _LOGGER.info(f"Dynamic host not available or invalid: {state_value}")
        except Exception as e:
            _LOGGER.warning(f"Could not read dynamic host: {e}")
        
        # If we have a configured URL, use it
        if self._api_url:
            _LOGGER.debug(f"Using configured API URL: {self._api_url}")
            return self._api_url
        
        # Last resort: use production IP
        port = self._config_entry.data.get("port", DEFAULT_PORT)
        fallback_url = f"http://192.168.0.99:{port}/api/v1/conversation"
        _LOGGER.info(f"No host configured and no dynamic host available, using fallback: {fallback_url}")
        return fallback_url

    async def async_process(
        self, user_input: conversation.ConversationInput
    ) -> conversation.ConversationResult:
        """Process a conversation turn."""
        _LOGGER.info("=" * 60)
        _LOGGER.info("NEW CONVERSATION REQUEST")
        _LOGGER.info("User input: %s", user_input.text)
        _LOGGER.info("Conversation ID: %s", user_input.conversation_id)
        _LOGGER.info("Device ID: %s", user_input.device_id)
        _LOGGER.info("Language: %s", user_input.language)
        
        try:
            # Get current API URL (may be dynamic)
            api_url = self._get_current_api_url()
            _LOGGER.info("Using API URL: %s", api_url)
            
            # Phase 3.5: Ultra-simple session management
            # Just use HA's conversation_id as our session ID
            # HA already tracks multi-turn conversations for us
            # No state tracking needed in the agent - keep it stateless
            session_id = f"voice_{user_input.conversation_id}"
            _LOGGER.info("Session ID: %s", session_id)
            
            # Prepare request payload for Sinatra app  
            payload = {
                "message": user_input.text,
                "context": {
                    "session_id": session_id,  # Derived from HA's conversation tracking
                    "conversation_id": user_input.conversation_id,  # Original HA ID for reference
                    "device_id": user_input.device_id,
                    "language": user_input.language,
                    "voice_interaction": True,
                    "timestamp": dt_util.utcnow().isoformat(),
                    # Add any additional context
                    "ha_context": {
                        "agent_id": self._attr_unique_id,
                        "user_id": getattr(user_input, "user_id", None),
                    }
                }
            }
            
            _LOGGER.debug("Sending payload to Sinatra: %s", payload)
            
            # Call Sinatra app using dynamic URL
            timeout = aiohttp.ClientTimeout(total=self._timeout)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.post(
                    api_url,
                    json=payload,
                    headers={"Content-Type": "application/json"}
                ) as response:
                    _LOGGER.info("Sinatra response status: %d", response.status)
                    if response.status != 200:
                        raise ConversationError(f"API error: {response.status}")
                    
                    result_data = await response.json()
                    
                    if not result_data.get("success", False):
                        raise ConversationError(f"Conversation failed: {result_data.get('error', 'Unknown error')}")
                    
                    conversation_data = result_data.get("data", {})
                    
                    # Route based on custom response type for async flow support
                    response_type = conversation_data.get("response_type", "normal")
                    _LOGGER.info("Processing response_type: %s", response_type)
                    
                    # Handle different response types
                    if response_type == "immediate_speech_with_background_tools":
                        return await self._handle_immediate_speech_with_background_tools(
                            conversation_data, user_input
                        )
                    elif response_type == "error":
                        return await self._handle_error_response(
                            conversation_data, user_input
                        )
                    else:
                        # Handle normal responses through the new handler
                        return await self._handle_normal_response(conversation_data, user_input)
                    
        except asyncio.TimeoutError:
            _LOGGER.error("Timeout calling Glitch Cube API")
            return self._create_error_response(user_input, "I'm having trouble thinking right now. Please try again.")
        
        except aiohttp.ClientError as e:
            _LOGGER.error("Client error calling Glitch Cube API: %s", str(e))
            return self._create_error_response(user_input, "I can't connect to my brain right now. Please try again.")
        
        except ConversationError as e:
            _LOGGER.error("Conversation error: %s", str(e))
            return self._create_error_response(user_input, "Something went wrong with my thinking. Please try again.")
        
        except Exception as e:
            _LOGGER.exception("Unexpected error in conversation processing")
            return self._create_error_response(user_input, "I encountered an unexpected error. Please try again.")

    # REMOVED: Complex bidirectional service call methods for Phase 3 simplification
    # All actions now handled by Sinatra via tools:
    # - _handle_suggested_actions() → Now handled by Sinatra tools (lighting_control, etc.)
    # - _handle_media_actions() → Now handled by Sinatra speech_synthesis tool
    # - _handle_tts_action() → Now handled by Sinatra speech_synthesis tool  
    # - _handle_audio_action() → Now handled by Sinatra tools
    #
    # This creates clean separation: HA = STT + hardware, Sinatra = conversation + tools

    def _extract_response_text(self, conversation_data):
        """Extract speech text from potentially nested response structure.
        
        Handles both simple string responses and complex nested objects from
        our enhanced conversation system. This fixes the TTS bug where nested
        objects were being passed directly to async_set_speech.
        """
        raw_response = conversation_data.get(RESPONSE_KEY, "")
        
        if isinstance(raw_response, dict):
            # Handle nested HA conversation API structure
            response_text = (
                # Try nested speech structure first (from action_done responses)
                raw_response.get("speech", {}).get("plain", {}).get("speech") or
                # Try simple response field
                raw_response.get("response") or
                # Try claude response in custom data
                str(raw_response.get("data", {}).get("custom_data", {}).get("claude_response", ""))[:100] or
                # Final fallback
                "I had some trouble with that response."
            )
        else:
            # Simple string response - convert to string safely
            response_text = str(raw_response) if raw_response else "I didn't understand that."
        
        # Ensure we always have valid speech text
        cleaned_text = response_text.strip()
        if not cleaned_text:
            cleaned_text = "Sorry, I'm having trouble speaking right now."
            
        _LOGGER.debug("Extracted response text: %s", cleaned_text[:100])
        return cleaned_text

    async def _handle_immediate_speech_with_background_tools(
        self, conversation_data, user_input
    ):
        """Handle immediate speech while tools execute in background.
        
        This fires TTS immediately without blocking, then returns a minimal
        ConversationResult to keep the session alive for potential follow-up.
        """
        speech_text = conversation_data.get("speech_text", "On it!")
        _LOGGER.info("🚀 Executing immediate TTS for background tools: %s", speech_text[:50])
        
        try:
            # Fire TTS immediately without blocking the response
            await self.hass.services.async_call(
                'tts',
                'cloud_say',
                {
                    'entity_id': 'media_player.square_voice',
                    'message': speech_text,
                    'language': 'en-US'
                },
                blocking=False  # Critical: don't wait for TTS completion
            )
            _LOGGER.info("✅ Immediate TTS service call successful")
        except Exception as e:
            _LOGGER.error("💥 Immediate TTS failed: %s", str(e))
        
        # Add delay before returning to prevent rapid triggering
        delay_seconds = conversation_data.get("continue_delay", 3)  # Default 3 seconds  
        _LOGGER.info("⏰ Adding %s second delay for background tools before re-enabling conversation", delay_seconds)
        await asyncio.sleep(delay_seconds)
        
        # Play sound alert when listening resumes after background tools
        await self._play_listening_resume_sound()
        
        # Return minimal result to keep session alive for follow-up
        intent_response = intent.IntentResponse(language=user_input.language)
        intent_response.async_set_speech(" ")  # Empty to prevent double-speak
        
        return conversation.ConversationResult(
            conversation_id=user_input.conversation_id,
            response=intent_response,
            continue_conversation=True  # Keep session alive for background results
        )

    async def _handle_error_response(self, conversation_data, user_input):
        """Handle error responses with appropriate messaging."""
        error_text = conversation_data.get("speech_text", "I encountered an error.")
        error_details = conversation_data.get("error_details", "")
        
        _LOGGER.error("🚨 Handling error response: %s", error_details)
        
        intent_response = intent.IntentResponse(language=user_input.language)
        intent_response.async_set_speech(error_text)
        
        return conversation.ConversationResult(
            conversation_id=user_input.conversation_id,
            response=intent_response,
            continue_conversation=False  # End conversation on error
        )

    async def _handle_normal_response(self, conversation_data, user_input):
        """Handle standard synchronous responses."""
        response_text = self._extract_response_text(conversation_data)
        
        intent_response = intent.IntentResponse(language=user_input.language)
        intent_response.async_set_speech(response_text)
        
        continue_conversation = conversation_data.get("continue_conversation", False)
        
        # Add configurable delay if continuing conversation to prevent rapid triggering
        if continue_conversation:
            delay_seconds = conversation_data.get("continue_delay", 3)  # Default 3 seconds
            _LOGGER.info("⏰ Adding %s second delay before re-enabling conversation to prevent rapid triggering", delay_seconds)
            await asyncio.sleep(delay_seconds)
            
            # Play sound alert when listening resumes
            await self._play_listening_resume_sound()
        
        _LOGGER.info("📢 Normal response: %s...", response_text[:50])
        _LOGGER.info("Continue conversation: %s", continue_conversation)
        
        return conversation.ConversationResult(
            conversation_id=user_input.conversation_id,
            response=intent_response,
            continue_conversation=continue_conversation
        )

    async def _play_listening_resume_sound(self):
        """Play a sound alert to indicate listening has resumed."""
        try:
            # Play a subtle chime sound to indicate listening is active
            await self.hass.services.async_call(
                'media_player',
                'play_media',
                {
                    'entity_id': 'media_player.square_voice',
                    'media_content_id': '/media/sounds/listening_resume.wav',  # Add this sound file
                    'media_content_type': 'audio/wav',
                },
                blocking=False
            )
            _LOGGER.info("🔔 Listening resume sound triggered")
        except Exception as e:
            _LOGGER.warning("⚠️ Could not play listening resume sound: %s", str(e))

    def _create_error_response(
        self, 
        user_input: conversation.ConversationInput, 
        error_message: str
    ) -> conversation.ConversationResult:
        """Create an error response."""
        intent_response = intent.IntentResponse(language=user_input.language)
        intent_response.async_set_speech(error_message)
        
        return conversation.ConversationResult(
            conversation_id=user_input.conversation_id,
            response=intent_response,
            continue_conversation=False,
        )


class ConversationError(Exception):
    """Custom exception for conversation errors."""