# Configuration

All configuration lives in **`config/initializers/config.rb`** — the single source of
truth. It reads ENV once at boot into `Rails.configuration.*`; the rest of the app reads
`Rails.configuration.*` and never touches `ENV` directly.

`.env` (gitignored) holds only:

1. **Required secrets** — no default; the app raises at boot if they're unset (tests use a
   dummy). dev + prod `.env` must set them.
2. **Genuine per-host overrides** — values that legitimately differ by machine.

Everything else has a version-controlled default here and needs **no** env var. To change a
default for everyone, edit `config.rb`; to override for one host, uncomment the var in that
host's `.env`. Most knobs can also be changed live from `rails c`
(e.g. `Rails.configuration.ai_model = "..."`) without a restart.

> **dev vs prod `.env` are identical except one line:** dev sets `USE_LOCAL_VISION=false`
> (no ollama model pulled), prod leaves it unset (on-host ollama vision is the default).

## Required secrets (raise at boot if missing)

| ENV var | `Rails.configuration` | Description |
|---|---|---|
| `OPENROUTER_API_KEY` | `openrouter_api_key` | OpenRouter key — brain, summarizers, and the OpenRouter vision fallback all route through it. |
| `HOME_ASSISTANT_TOKEN` | `home_assistant_token` | HASS long-lived access token. dev + prod hit the same HASS instance, so the same token works. |

## Optional secrets (safe to omit)

| ENV var | `Rails.configuration` | Default | Description |
|---|---|---|---|
| `HELICONE_API_KEY` | `helicone_api_key` | `nil` | Optional LLM observability proxy. |
| `QUALSPEC_API_KEY` | *(read by the qualspec gem, not config.rb)* | — | Dev/test eval harness; point it at the OpenRouter key. |

## Models (all have version-controlled defaults)

| ENV var | `Rails.configuration` | Default | Description |
|---|---|---|---|
| `DEFAULT_AI_MODEL` | `ai_model` | `deepseek/deepseek-v4-flash:nitro` | The one brain model for the conversation flow. |
| `SUMMARIZER_MODEL` | `summarizer_model` | `google/gemini-3.5-flash` | Model for the background summarizer tiers (interaction / persona+handoff / overall). |
| `CAMERA_VISION_MODEL` | `camera_vision_model` | `google/gemini-3.5-flash` | Primary vision model for camera-snapshot descriptions (OpenRouter path). |
| `VISION_FALLBACK_MODEL` | `vision_fallback_model` | `qwen/qwen3.7-max` | Retried once if the primary vision model raises or returns empty. |
| `HASS_ACTION_AGENT` | `hass_action_agent` | `conversation.anthropic_claude_sonnet_4_6` | HASS conversation agent the cube offloads plain-English `actions` to. |

## Home Assistant

| ENV var | `Rails.configuration` | Default | Description |
|---|---|---|---|
| `HOME_ASSISTANT_URL` | `home_assistant_url` | `http://glitch.local:8123` | HASS base URL. dev + prod share one instance at `glitch.local`; test relies on this exact host to match VCR cassettes. |
| `HOME_ASSISTANT_TIMEOUT` | `home_assistant_timeout` | `30` | HASS HTTP timeout in seconds. |

## Camera / local vision

| ENV var | `Rails.configuration` | Default | Description |
|---|---|---|---|
| `USE_LOCAL_VISION` | `use_local_vision` | `true` | Describe snapshots with an on-host ollama model (image never leaves the box). Only the literal `"false"` disables it → OpenRouter path. **The one line that differs dev↔prod.** |
| `LOCAL_VISION_URL` | `local_vision_url` | `http://localhost:11434` | ollama endpoint. |
| `LOCAL_VISION_MODEL` | `local_vision_model` | `qwen3-vl:4b` | On-host ollama vision model. |
| `DISABLE_CAMERA` | `disable_camera` | `false` | Kill switch: no `CameraDescriptionJob` enqueued and `ContextBuilder` omits the camera block. Can also be toggled via `input_boolean.disable_camera` on HASS. |

## Misc

| ENV var | `Rails.configuration` | Default | Description |
|---|---|---|---|
| `OPENROUTER_APP_NAME` | `openrouter_app_name` | `GlitchCube` | Sent to OpenRouter for attribution. |
| `OPENROUTER_SITE_URL` | `openrouter_site_url` | `https://glitchcube.com` | Sent to OpenRouter for attribution. |
| `GLITCH_PERCENT` | `glitch_percent` | `3` (forced `0` in test) | Odds (%) a turn leaks its inner monologue aloud instead of the intended speech. |

## Non-config env vars

A few env vars are read directly by libraries/tooling, not by `config.rb`:

- `PGGSSENCMODE=disable` — read by libpq (the pg driver) straight from the process env to
  disable GSSAPI encryption negotiation against the local Postgres.
- `HISTORY_WINDOW_MINUTES` / `HISTORY_WINDOW_LIMIT` — `config/initializers/conversation_config.rb`
  (conversation history window; default 10 / 8).

## Keeping this in sync

When you add, remove, or rename a knob in `config/initializers/config.rb`, update this table
in the same change. This doc and that file are meant to stay 1:1.
