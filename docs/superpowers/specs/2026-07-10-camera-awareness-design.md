# Camera Awareness — design

> **SUPERSEDED (2026-07-11):** the HASS-side pipeline described here (mediamtx RTSP →
> generic camera → LLMVision) was replaced by a Rails-owned one-shot capture. See
> `2026-07-11-rails-camera-snapshot-design.md`. The prompt-injection side (input_text →
> ContextBuilder) and the stale-clear automation described here are still accurate.

**Date:** 2026-07-10
**Status:** superseded — see banner above

## Goal

Give the cube a lightweight sense of who/what is physically in front of it. A camera
snapshot is run through `llmvision.image_analyzer`, its short description is stashed in
an `input_text`, and that description is injected into the brain's prompt (below the
world-state block) whenever it's present. The look refreshes automatically at the start
of every conversation, and the cube can ask for a fresh look mid-conversation ("refresh
my camera"). We deliberately do **not** analyze the camera continuously — vision calls
cost money — so the description is short-lived and only exists right around a conversation.

Non-goal for now: a local Ollama vision model (later; makes continuous analysis cheaper,
but this design doesn't depend on it — swapping the provider is a one-line change in the
script).

## Shape (one line)

A button, a script that sets an `input_text` from the vision response, that `input_text`
injected into the prompt under the world state when present, and an automation that clears
it after 3 minutes so it never goes stale.

## Isolation via the button

The Assist agent (the HASS action agent that decodes the cube's plain-English actions) is
exposed **exactly one** camera-related entity: `input_button.refresh_camera_description`.
It never sees the camera entity or `llmvision.*` — it can only press the button. All the
real work (calling the analyzer, writing the `input_text`) happens in a script/automation
the agent can't reach. This keeps the agent from poking at camera entities directly.

## HASS helpers (in `data/homeassistant/packages/glitchcube_core.yaml`)

Added alongside the existing helpers:

```yaml
input_text:
  current_camera_state:
    name: "Current Camera State"
    initial: ""
    max: 255
    icon: mdi:cctv

input_button:
  refresh_camera_description:
    name: "Refresh Camera Description"
    icon: mdi:camera-iris
```

## Script (in `data/homeassistant/scripts.yaml`)

```yaml
refresh_camera_description:
  alias: Refresh Camera Description
  description: >-
    Take a snapshot from the cube's camera, run it through the vision analyzer, and store
    a short description of what's in front of the cube in input_text.current_camera_state.
  sequence:
    - action: llmvision.image_analyzer
      data:
        provider: 01KX77D35KPJHRNVGDTB7RRX1C
        image_entity:
          - camera.192_168_68_75
        include_filename: true
        message: >-
          Focus on the people in the picture — they are interacting with an interactive art
          project that just asked for a snapshot of what it currently sees. In ONE or TWO
          short sentences (max 255 characters): how many people, their fashion / vibe, and
          anything notable. If no one is there, say so briefly.
      response_variable: results
    - action: input_text.set_value
      target:
        entity_id: input_text.current_camera_state
      data:
        value: "{{ (results.response_text | default('', true))[:255] }}"
```

The `[:255]` truncation stays even though the prompt asks for ≤255 chars — belt and
suspenders, since `input_text` rejects over-length values.

## Automations (in `data/homeassistant/automations.yaml`)

**Refresh** — fires on the button press (cube's manual "refresh my camera") *or* the
satellite entering `listening` (conversation start — covers both wake-word and the
physical button on the Voice PE, since both drive the satellite to `listening`):

```yaml
- alias: "Camera: refresh description"
  triggers:
    - trigger: state
      entity_id: input_button.refresh_camera_description  # press event
    - trigger: state
      entity_id: assist_satellite.cube_cube_voice_assist_satellite
      to: listening
  conditions: []
  actions:
    - action: script.refresh_camera_description
```

No debounce: a conversation round (STT + brain + TTS) is far longer than the refresh, so
this won't be hammered; and if the cube explicitly asks, it *wants* a fresh look. The
firmware's occasional `responding→idle→listening` blip mid-turn may cost one extra vision
call — that's fine.

**Clear** — once the description has sat unchanged for 3 minutes, blank it so a stale look
never lingers in the prompt. The non-empty condition is the guard that keeps clearing to
`""` from re-triggering itself:

```yaml
- alias: "Camera: clear stale description"
  triggers:
    - trigger: state
      entity_id: input_text.current_camera_state
      for: "00:03:00"
  conditions:
    - "{{ states('input_text.current_camera_state') | trim != '' }}"
  actions:
    - action: input_text.set_value
      target:
        entity_id: input_text.current_camera_state
      data:
        value: ""
```

## Rails change (in `app/services/prompts/context_builder.rb`)

The description gets its **own block, below the world-state paragraph** (item 6, the most
live signal, closest to the raw message history) — not folded into the world-state
sentence. Omitted entirely when the `input_text` is blank; because the clear automation
owns staleness, Rails does a dumb presence check with no timestamp logic.

```ruby
CAMERA_ENTITY = "input_text.current_camera_state"

# in build, after world_state_context:
#   world_state_context,
#   camera_context

# 6. The live camera view — its own block, below ambient world state, closest to the
#    messages. Omitted when empty; HASS clears it when stale, so presence == fresh.
def camera_context
  desc = HomeAssistantService.entity(CAMERA_ENTITY)&.dig("state")
  return nil if desc.blank?

  "Right now, your camera shows: #{desc.squish}"
rescue => e
  warn_nil(CAMERA_ENTITY, e)
end
```

Also update the file's header comment (add item 6) and the ContextBuilder ordering list in
`CLAUDE.md` (currently 5 items) to mention the camera view.

## Data flow

- **Auto (conversation start):** wake-word / Voice PE button → satellite `listening` →
  refresh automation → script → llmvision (~2–4s) → `input_text`. Not ready for turn 1's
  reply; fresh by turn 2. Expected and acceptable.
- **Every turn:** `ContextBuilder#camera_context` reads the `input_text`; if present,
  injects the line below the world state → brain prompt.
- **Manual:** cube emits a "refresh my camera" action → Assist agent presses
  `input_button.refresh_camera_description` → same automation/script → flows in next turn.
- **Staleness:** clear automation blanks the `input_text` after 3 min → it drops out of the
  prompt on its own.

## Verification

1. From HASS dev tools, run `script.refresh_camera_description` → confirm
   `input_text.current_camera_state` fills with a short description.
2. Confirm `Prompts::ContextBuilder.build` output includes the "Right now, your camera
   shows:" line below the world-state block (Rails console or a request).
3. Wait 3 min → confirm the `input_text` clears and the line drops out of the prompt.
4. Drive a real conversation: say "hey glitchcube", confirm the description appears by
   turn 2; ask the cube to "refresh your camera" and confirm it re-runs.

## What we intentionally left out

- **No debounce / no timestamp helper.** Conversation cadence is the natural rate limit.
- **No separate clearing timer / `input_datetime`.** The `input_text`'s own state + the
  `for: 3min` state trigger is enough.
- **No Rails-side freshness check.** HASS owns staleness; Rails checks presence only.
- **No new camera entities exposed to the Assist agent.** Only the button.
```
