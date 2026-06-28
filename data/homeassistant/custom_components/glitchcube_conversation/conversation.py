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
    log_dir = Path("/config/logs")
    log_dir.mkdir(exist_ok=True)

    file_handler = logging.FileHandler(log_dir / "glitchcube_conversation.log")
    file_handler.setLevel(logging.DEBUG)

    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    file_handler.setFormatter(formatter)

    _LOGGER.addHandler(file_handler)
    _LOGGER.setLevel(logging.DEBUG)

    return _LOGGER

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
        host = config_entry.data.get("host", "")
        port = config_entry.data.get("port", DEFAULT_PORT)
        name = config_entry.data.get("name", "")

        if name:
            self._attr_name = f"Glitch Cube - {name.title()}"
        elif not host:
            self._attr_name = f"Glitch Cube (Dynamic IP:{port})"
        else:
            self._attr_name = f"Glitch Cube ({host}:{port})"

        if not host:
            self._api_url = None
        else:
            self._api_url = f"http://{host}:{port}/api/v1/conversation"

        self._attr_unique_id = f"{DOMAIN}_{config_entry.entry_id}"
        self._timeout = DEFAULT_TIMEOUT

        _LOGGER.info("Initialized Glitch Cube conversation agent: %s", self._attr_name)

    @property
    def supported_languages(self) -> list[str]:
        """Return list of supported languages."""
        return SUPPORTED_LANGUAGES

    def _get_current_api_url(self) -> str:
        """Get the current API URL, checking for dynamic host first."""
        try:
            glitchcube_host_state = self.hass.states.get("input_text.glitchcube_host")
            if (glitchcube_host_state and
                glitchcube_host_state.state and
                glitchcube_host_state.state not in ["unknown", "unavailable", ""]):

                dynamic_host = glitchcube_host_state.state.strip()
                # dynamic_host may already include the port (e.g. "192.168.68.50:4567")
                if ":" in dynamic_host:
                    api_url = f"http://{dynamic_host}/api/v1/conversation"
                else:
                    port = self._config_entry.data.get("port", DEFAULT_PORT)
                    api_url = f"http://{dynamic_host}:{port}/api/v1/conversation"
                _LOGGER.debug(f"Using dynamic host from input_text: {dynamic_host}")
                return api_url
            else:
                state_value = glitchcube_host_state.state if glitchcube_host_state else "None"
                _LOGGER.info(f"Dynamic host not available or invalid: {state_value}")
        except Exception as e:
            _LOGGER.warning(f"Could not read dynamic host: {e}")

        if self._api_url:
            _LOGGER.debug(f"Using configured API URL: {self._api_url}")
            return self._api_url

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
            api_url = self._get_current_api_url()
            _LOGGER.info("Using API URL: %s", api_url)

            session_id = f"voice_{user_input.conversation_id}"
            _LOGGER.info("Session ID: %s", session_id)

            payload = {
                "message": user_input.text,
                "context": {
                    "session_id": session_id,
                    "conversation_id": user_input.conversation_id,
                    "device_id": user_input.device_id,
                    "language": user_input.language,
                    "voice_interaction": True,
                    "timestamp": dt_util.utcnow().isoformat(),
                    "ha_context": {
                        "agent_id": self._attr_unique_id,
                        "user_id": getattr(user_input, "user_id", None),
                    }
                }
            }

            _LOGGER.debug("Sending payload: %s", payload)

            timeout = aiohttp.ClientTimeout(total=self._timeout)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.post(
                    api_url,
                    json=payload,
                    headers={"Content-Type": "application/json"}
                ) as response:
                    _LOGGER.info("Response status: %d", response.status)
                    if response.status != 200:
                        raise ConversationError(f"API error: {response.status}")

                    result_data = await response.json()

                    if not result_data.get("success", False):
                        raise ConversationError(f"Conversation failed: {result_data.get('error', 'Unknown error')}")

                    conversation_data = result_data.get("data", {})
                    response_type = conversation_data.get("response_type", "normal")
                    _LOGGER.info("Processing response_type: %s", response_type)

                    if response_type == "immediate_speech_with_background_tools":
                        return await self._handle_immediate_speech_with_background_tools(
                            conversation_data, user_input
                        )
                    elif response_type == "error":
                        return await self._handle_error_response(conversation_data, user_input)
                    else:
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

    def _extract_response_text(self, conversation_data):
        """Extract speech text from potentially nested response structure."""
        raw_response = conversation_data.get(RESPONSE_KEY, "")

        if isinstance(raw_response, dict):
            response_text = (
                raw_response.get("speech", {}).get("plain", {}).get("speech") or
                raw_response.get("response") or
                str(raw_response.get("data", {}).get("custom_data", {}).get("claude_response", ""))[:100] or
                "I had some trouble with that response."
            )
        else:
            response_text = str(raw_response) if raw_response else "I didn't understand that."

        cleaned_text = response_text.strip()
        if not cleaned_text:
            cleaned_text = "Sorry, I'm having trouble speaking right now."

        _LOGGER.debug("Extracted response text: %s", cleaned_text[:100])
        return cleaned_text

    async def _handle_immediate_speech_with_background_tools(self, conversation_data, user_input):
        """Handle immediate speech while tools execute in background."""
        speech_text = conversation_data.get("speech_text", "On it!")
        _LOGGER.info("🚀 Immediate speech (background tools running): %s", speech_text[:50])

        intent_response = intent.IntentResponse(language=user_input.language)
        intent_response.async_set_speech(speech_text)

        return conversation.ConversationResult(
            conversation_id=user_input.conversation_id,
            response=intent_response,
            continue_conversation=True,
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
            continue_conversation=False,
        )

    async def _handle_normal_response(self, conversation_data, user_input):
        """Handle standard synchronous responses."""
        response_text = self._extract_response_text(conversation_data)
        continue_conversation = conversation_data.get("continue_conversation", False)

        _LOGGER.info("📢 Normal response (%s): %s...", "continue" if continue_conversation else "end", response_text[:60])

        intent_response = intent.IntentResponse(language=user_input.language)
        intent_response.async_set_speech(response_text)

        return conversation.ConversationResult(
            conversation_id=user_input.conversation_id,
            response=intent_response,
            continue_conversation=continue_conversation,
        )

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
