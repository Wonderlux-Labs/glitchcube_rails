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

1. **Base look** (persistent): the resting color/effect/brightness of each strip — whatever it
   currently is, however it got there (a **persona switch** → persona color solid, a **brain
   light command** → e.g. red head / purple body, a show, a manual call). Persists between turns
   and is captured by snapshot at the start of each turn.
2. **Expression overlay** (transient, per turn): brighten → pulse → sound-react, each on the
   strips' *current* colors. Never invents a color.
3. **Restore-or-replace** (turn end): if a brain command landed this turn, its new look is
   already live and stays. Otherwise the strips snap back to the base look.

## The base look is snapshotted at turn start (HASS owns the storage)

We cannot recover the base by reading the live strips at turn end — by then the overlay has
overwritten their effect/brightness. So we snapshot the resting look **at the start of the
turn**, before the overlay touches anything, and let HASS store it:

- `scene.before_conversation_turn` — created fresh each turn with
  `scene.create({scene_id: before_conversation_turn, snapshot_entities: [head, body]})`. HASS
  captures everything about those two lights (color, effect, brightness) automatically.

Snapshotting at turn start (not on base-change events) means we make **no assumption about how
the lights got their current look** — a persona switch, a brain command, a show, a manual call,
anything. We just capture reality as it is when the cube starts paying attention, and restore it
with `scene.turn_on scene.before_conversation_turn`.

## The deferral (as requested)

The brain's light command must not fight the "talking" effect. `set_cube_lights` gains a
`wait_template` at the top of its sequence so the command "takes its arguments and waits,"
landing when the cube stops talking rather than flickering mid-speech.

> **Which "done talking" signal:** the firmware blips `responding → idle → listening` ~2s into a
> long response *before audio starts* (documented in the mic-guard automation), so a naive
> `not responding` wait can release early. The robust end-of-speech signal the mic-guard already
> trusts is the voice media player leaving `playing`. The wait therefore keys off
> `media_player.cube_cube_voice_media_player` not being `playing` (timeout ~25s,
> `continue_on_timeout: true`). This is a timing detail worth confirming on hardware — if it
> releases early in practice, the fallback is to defer via the media-player edge in the
> automation instead of a level template in the script.

## The command flag (settles the turn-end decision)

`input_boolean.cube_light_command_this_turn` marks "a brain light command is being handled this
turn":

- **Set on** by `set_cube_lights` as its **very first action** — the instant the command is
  received, *before* it waits out the cube's speech and *before* it paints anything.
- **Reset off** at the start of each turn, together with the snapshot.
- **Read** by the turn-end handler: flag on → a command is in flight / already live, do **not**
  restore (leave it). Flag off → `scene.turn_on scene.before_conversation_turn`.

**Why "first action" matters — the same-edge race.** The turn-end restore and the
`set_cube_lights` `wait_template` are released by the *same* event (the media player leaving
`playing`). If the flag were only set *after* the wait releases, the restore handler could read
it before the command's paint set it — a coin flip. Because the action agent calls
`set_cube_lights` *during* the turn (while the cube is still speaking/decoding), setting the flag
as the script's first line flips it **seconds before** TTS-end in the normal case. The flag-read
at turn-end is then reading a value written far upstream — no timing dependence. A short delay on
the restore branch stays as cheap insurance, but correctness rests on the causal ordering, not
the delay.

**Residual (accepted):** if the agent is slow and calls `set_cube_lights` only *after* TTS
already ended, the restore will have fired first (flag was still off) and the command then paints
over it — a brief flash of the restored base before the new look. Correct end state, minor
visual, inherent to not knowing a command is coming in advance. Not worth engineering around.

The flag is the only piece of our own bookkeeping; the base look itself is entirely HASS-stored.

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
persona color at full brightness, effect `Solid`. That's all — no scene bookkeeping; the next
turn's start-snapshot captures whatever this leaves.

Color map (from the existing ring automation):
`buddy [255,220,0] · neon [255,0,128] · zorp [160,0,255] · crash [0,255,65] · jax [0,120,255] · default [255,255,255]`

### 3. `automations/persona/persona_switcher.yaml` — edit
- Replace the inline `light.cube_cube_voice_led_ring` `turn_on` (the ring color map) with a
  call to `script.sync_lights_to_persona`, which now owns head + body + ring together.
- Keep the Assist pipeline `select.select_option` step and the top-light step as-is.
- (Optional) add a `homeassistant` `start` trigger so a reboot leaves the cube showing its
  persona color at rest. Cosmetic only now — the turn-start snapshot no longer depends on it.

### 4. `automations/lights/cube_expression.yaml` — new automation
Triggers on `assist_satellite.cube_cube_voice_assist_satellite` and the voice media player,
reusing the mic-guard disambiguation. All branches guarded by
`input_boolean.persona_switching == off` (the grand-entrance show owns the lights while up).

| Trigger | Condition | Action |
|---|---|---|
| `to: listening` | not media playing **and** mute switch off (genuine listening, not the mid-speech blip) | reset `cube_light_command_this_turn` off; `scene.create` `before_conversation_turn` snapshotting head+body; **then** `light.turn_on` head+body `brightness_pct: 100` (keep color+effect) |
| `to: processing` | — | `light.turn_on` head+body `effect: Breathe` (keep color) |
| `to: responding` | — | `light.turn_on` head+body `effect: <volume-reactive>` (keep color) |
| `media_player … from: playing` (true end of TTS) | `persona_switching` off | delay ~0.5s; **if** `cube_light_command_this_turn` off → `scene.turn_on scene.before_conversation_turn` |
| `to: idle for 10s` (stuck-state safety) | `persona_switching` off, not media playing | `scene.turn_on scene.before_conversation_turn`; reset flag off |

The snapshot must run **before** the brightness bump so the scene holds the true resting look,
not the woken-up one.

### 5. `scripts/lights/cube_lights.yaml` — edit `set_cube_lights`
Prepend to the sequence, **in this order** — claim the turn first (so the turn-end restore sees
the flag no matter how the timing falls), *then* wait out the cube's speech (keyed off the media
player, not `responding` — see the deferral note):
```yaml
  # Claim the turn BEFORE waiting, so the same-edge TTS-end restore can never beat us to the flag.
  - action: input_boolean.turn_on
    target: { entity_id: input_boolean.cube_light_command_this_turn }
  - wait_template: "{{ not is_state('media_player.cube_cube_voice_media_player', 'playing') }}"
    timeout: "00:00:25"
    continue_on_timeout: true
```
Then the existing `light.turn_on` applies the look. No scene bookkeeping here — the command's new
look is simply left live, and the *next* turn's start-snapshot captures it as that turn's resting
base. (The effect-list / description curation from the WLED cleanup is already applied and is
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

1. Resting: red head, purple body.
2. `listening` → snapshot `before_conversation_turn` (red/purple); flag reset off; both brighten
   to full (bright red / bright purple).
3. `processing` → both `Breathe` on their colors.
4. `responding` → both `Gravcenter`, pulsing red / purple to the voice.
5. TTS ends → flag still off → `scene.turn_on before_conversation_turn` → back to resting
   red / purple.

With a command ("go deep blue"): the action agent calls `set_cube_lights` *during* the turn — its
first action sets the flag on immediately, then it waits out the cube's speech, then paints blue.
TTS-end (fired by the same media-stop event) reads the flag, sees it was set seconds ago → skips
restore → blue stays live and becomes the resting base that the *next* turn's step-2 snapshot
captures.

## Edge cases

- **Mid-speech `responding→idle→listening` blip:** the listening branch's `not media playing`
  + `mute off` conditions reject it (same tell mic-guard uses); the real end signal is the
  media player leaving `playing`.
- **`continue_conversation` multi-turn:** each turn snapshots its own resting look at listening
  and resets the flag; chains correctly.
- **Turn errors before TTS plays:** the 10s-idle safety restores the snapshot and clears the flag.
- **Grand entrance:** `persona_switching` guard keeps the overlay hands-off while the show owns
  the strips; normal expression resumes when the boolean drops.
- **Restore vs. next snapshot (minor):** turn N's TTS-end restore and turn N+1's listening
  snapshot are at different turn boundaries and separated by the visitor's next utterance, so
  they don't normally overlap. If a very fast back-to-back turn ever snapshots before the restore
  settles, worst case is one turn's resting look being slightly off — cosmetic, and a thing to
  watch on hardware rather than pre-engineer around.

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
