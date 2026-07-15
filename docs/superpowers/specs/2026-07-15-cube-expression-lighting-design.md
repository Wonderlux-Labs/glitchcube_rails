# Cube Expression Lighting — Design

**Date:** 2026-07-15
**Status:** Approved design, pending implementation plan
**Scope:** Home Assistant config only (`data/homeassistant/`). No Rails changes.

## Problem

The cube's two show strips — the head (`light.glitch_head_wled`, ~30 LEDs) and body
(`light.cube_body_wled`, ~60 LEDs) on one sound-reactive WLED controller — currently
have no live tie to what the cube is *doing* in a conversation. We want the cube to
physically emote through a turn: wake up when it hears you, think, talk, and settle.

Two asks:

1. **On persona switch**, sync the head and body strips to the new persona's signature
   color (the same color already applied to the Voice PE LED ring), so the cube visibly
   "becomes" the new persona.
2. **A per-turn expression overlay** driven by the assist-satellite state machine:
   - **listening** → both strips brighten to full ("just woke up")
   - **processing** → both strips gently pulse ("thinking")
   - **responding** → both strips run a sound-reactive effect that pulses to the cube's
     own voice ("talking")
   - **turn end** → either the brain changed the look this turn (its light command lands),
     or nothing did (strips return to exactly how they looked before listening started).

## Core model — three layers on two strips

The key insight (from the design conversation): the expression overlay is **content-agnostic**.
It does **not** impose the persona color — it modulates whatever color each strip currently
holds. If the cube previously set a *romantic red head + purple body*, then listening
brightens *that red* and *that purple*, processing pulses them, and responding runs a
sound-reactive effect **using those same colors**.

Three layers:

1. **Base look** (persistent): the resting color/effect/brightness of each strip. Changed
   only by two explicit events — a **persona switch** (both strips → persona color, solid)
   or a **brain light command** (`set_cube_lights`, e.g. red head / purple body). Persists
   between turns.
2. **Expression overlay** (transient, per turn): brighten → pulse → sound-react, each on the
   strips' *current* colors. Never invents a color.
3. **Restore-or-replace** (turn end): if a brain command landed this turn, its new look is
   already live and stays. Otherwise the strips snap back to the base look.

## The base look is stored, not read live

We cannot recover the base by reading the live strips at turn end — by then the overlay has
overwritten their effect/brightness. Instead the base is **stored as a scene** that is
(re)created only on the two base-change events:

- `scene.cube_light_base` — a dynamically created scene (`scene.create`) snapshotting
  `light.glitch_head_wled` + `light.cube_body_wled` (WLED captures color, effect, brightness).

Because the snapshot is taken only when the base genuinely changes (persona switch, or a brain
command after it applies), it never captures an overlay. "Restore" = `scene.turn_on
scene.cube_light_base`. This sidesteps every race with the transient overlay.

> The scene lives in memory, not `scenes.yaml`. It is re-established on HA start via the
> persona-sync running on the `homeassistant start` trigger (below), so a base always exists
> before the first turn.

## The deferral (as requested)

The brain's light command must not fight the "talking" effect. `set_cube_lights` gains a
`wait_template` at the top of its sequence: **if the satellite is `responding`, wait until it
isn't** (timeout ~25s, `continue_on_timeout: true`). So the command "takes its arguments and
waits," landing the instant the cube stops talking — replacing the base look rather than
flickering mid-speech.

## The command flag (settles the turn-end decision)

`input_boolean.cube_light_command_this_turn` marks "a brain light command landed this turn":

- **Set on** by `set_cube_lights` when it applies (right after the wait releases).
- **Reset off** at the start of each genuine listening (new turn).
- **Read** by the turn-end handler: flag on → a command look is already live, do **not**
  restore (leave it). Flag off → restore `scene.cube_light_base`.

Because restore is *skipped* whenever a command landed, restore and command-apply are mutually
exclusive — no race between them. `set_cube_lights` still re-snapshots `scene.cube_light_base`
after applying, so the *next* turn's restore targets the new look.

## Components (files)

### 1. `packages/glitchcube_core.yaml` — new helper
Add under `input_boolean:`:
```yaml
  cube_light_command_this_turn:
    name: "Cube light command landed this turn"
    initial: false
    icon: mdi:lightbulb-on-outline
```

### 2. `scripts/lights/sync_lights_to_persona.yaml` — new script (owns the color map)
Centralizes the persona→RGB map (currently duplicated across the ring and the top-light
script). Reads `input_select.current_persona`, sets head + body + Voice PE ring to the
persona color at full brightness, effect `Solid`, then re-snapshots `scene.cube_light_base`
and resets `cube_light_command_this_turn` off.

Color map (from the existing ring automation):
`buddy [255,220,0] · neon [255,0,128] · zorp [160,0,255] · crash [0,255,65] · jax [0,120,255] · default [255,255,255]`

### 3. `automations/persona/persona_switcher.yaml` — edit
- Add a `homeassistant` `start` trigger (so boot establishes the base scene + pipeline).
- Replace the inline `light.cube_cube_voice_led_ring` `turn_on` (the ring color map) with a
  call to `script.sync_lights_to_persona`, which now owns head + body + ring together.
- Keep the Assist pipeline `select.select_option` step and the top-light step as-is.

### 4. `automations/lights/cube_expression.yaml` — new automation
Triggers on `assist_satellite.cube_cube_voice_assist_satellite` and the voice media player,
reusing the mic-guard disambiguation. All branches guarded by
`input_boolean.persona_switching == off` (the grand-entrance show owns the lights while up).

| Trigger | Condition | Action |
|---|---|---|
| `to: listening` | not media playing **and** mute switch off (genuine listening, not the mid-speech blip) | reset `cube_light_command_this_turn` off; `light.turn_on` head+body `brightness_pct: 100` (keep color+effect) |
| `to: processing` | — | `light.turn_on` head+body `effect: Breathe` (keep color) |
| `to: responding` | — | `light.turn_on` head+body `effect: <volume-reactive>` (keep color) |
| `media_player … from: playing` (true end of TTS) | `persona_switching` off | delay ~0.5s; **if** `cube_light_command_this_turn` off → `scene.turn_on scene.cube_light_base` |
| `to: idle for 10s` (stuck-state safety) | `persona_switching` off, not media playing | `scene.turn_on scene.cube_light_base`; reset flag off |

### 5. `scripts/lights/cube_lights.yaml` — edit `set_cube_lights`
Prepend to the sequence, before the existing `light.turn_on`:
```yaml
  - wait_template: "{{ not is_state('assist_satellite.cube_cube_voice_assist_satellite', 'responding') }}"
    timeout: "00:00:25"
    continue_on_timeout: true
```
Append, after the existing `light.turn_on`:
```yaml
  - action: input_boolean.turn_on
    target: { entity_id: input_boolean.cube_light_command_this_turn }
  - action: scene.create
    data:
      scene_id: cube_light_base
      snapshot_entities:
        - light.glitch_head_wled
        - light.cube_body_wled
```
(The effect-list / description curation from the WLED cleanup is already applied and is
independent of this change.)

## Effect choices (tunable on hardware)

- **Pulse (processing):** `Breathe` — fades the primary color in/out, color unchanged. ✔
- **Sound-reactive talk (responding):** default `Gravcenter` — a volume bar from center in the
  primary color; reacts to the mic, does **not** rainbow the color. Alternates to taste-test on
  device: `Pixelwave`, `Puddlepeak`, `Gravfreq`. (Avoid `GEQ`-family and palette-driven
  effects here — they recolor.)

The WLED controller's mic is **always on** (confirmed), independent of the Voice PE mic that
gets muted during `responding`, so the talk effect genuinely pulses to the cube's own voice.

## Turn walkthrough (romantic red head / purple body, no command)

1. Resting: red head, purple body (base scene holds this).
2. `listening` → both brighten to full (bright red / bright purple); flag reset off.
3. `processing` → both `Breathe` on their colors.
4. `responding` → both `Gravcenter`, pulsing red / purple to the voice.
5. TTS ends → flag still off → restore `scene.cube_light_base` → back to resting red / purple.

With a command ("go deep blue"): at step 4 `set_cube_lights` waits out `responding`, then
paints blue, sets the flag, re-snapshots base = blue. TTS-end sees flag on → skips restore →
blue stays and becomes the new base.

## Edge cases

- **Mid-speech `responding→idle→listening` blip:** the listening branch's `not media playing`
  + `mute off` conditions reject it (same tell mic-guard uses); the real end signal is the
  media player leaving `playing`.
- **`continue_conversation` multi-turn:** flag resets each genuine listening; base re-snapshotted
  on each command; chains correctly across turns.
- **Turn errors before TTS plays:** the 10s-idle safety restores base and clears the flag.
- **Grand entrance:** `persona_switching` guard keeps the overlay hands-off while the show owns
  the strips; normal expression resumes when the boolean drops.
- **Fresh HA boot:** `homeassistant start` trigger runs `sync_lights_to_persona`, establishing
  the base scene before any turn.

## Testing / verification

- `bundle exec ruby -ryaml -e 'YAML.load_file(...)'` (or equivalent) on each new/edited YAML.
- HASS config check (`ha core check` on the box, or dev VM reload) — no schema errors.
- Live smoke on the dev HASS VM: drive a conversation, watch head/body through
  listening/processing/responding, confirm restore vs. command-replace, confirm persona switch
  syncs both strips, confirm grand entrance is unaffected.
- Hardware taste-test: pick the final responding effect; confirm scene restore reproduces a
  running base effect (not just solid color) on the WLED integration.

## Out of scope

- The Govee top light (`light.top_light`) — internal-only, being phased out; its scripts stay
  as-is.
- Exposing any of this to the Assist action agent (the overlay is automation-owned, not a tool).
- Rails-side changes.
