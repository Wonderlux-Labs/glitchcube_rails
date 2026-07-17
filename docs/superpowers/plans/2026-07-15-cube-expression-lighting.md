> **SUPERSEDED 2026-07-17:** the cube_expression automation and its cube_light_command_this_turn flag were REMOVED — the head cube is now the Voice PE's firmware-controlled LED ring (listening/processing effects live in firmware) and set_cube_lights drives a single body strip (light.cube_body_wled, no led_strip field). Kept as historical design record.

# Cube Expression Lighting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the cube's head + body WLED strips physically emote through a conversation turn (wake / think / talk) as a content-agnostic overlay on their current colors, and sync both strips to the persona color on persona switch.

**Architecture:** Pure Home Assistant config (`data/homeassistant/`), no Rails. A new `cube_expression` automation keys off the `assist_satellite` + voice `media_player` state machine (reusing the mic-guard's hardened signals) to snapshot the resting look at turn start, apply a brighten→Breathe→volume-reactive overlay, and at end-of-speech either keep a brain-commanded look or restore the snapshot. The `set_cube_lights` script defers commands past the cube's speech and claims the turn via a flag. A `sync_lights_to_persona` script centralizes the persona→color map.

**Tech Stack:** Home Assistant automations/scripts/packages (YAML), WLED light integration, `scene.create`/`scene.turn_on`.

## Global Constraints

- **HASS-side only.** No Rails code, no changes outside `data/homeassistant/`.
- **Entity IDs (exact, used across tasks):**
  - Satellite: `assist_satellite.cube_cube_voice_assist_satellite`
  - Voice media player: `media_player.cube_cube_voice_media_player`
  - Voice mic mute switch: `switch.cube_cube_voice_mute`
  - Voice LED ring: `light.cube_cube_voice_led_ring`
  - Head strip: `light.glitch_head_wled`
  - Body strip: `light.cube_body_wled`
  - Persona select: `input_select.current_persona`
  - Show guard: `input_boolean.persona_switching`
  - New command flag: `input_boolean.cube_light_command_this_turn`
  - Snapshot scene: `scene.before_conversation_turn` (created dynamically)
- **Persona→RGB map (verbatim, one source of truth):** `buddy [255,220,0]`, `neon [255,0,128]`, `zorp [160,0,255]`, `crash [0,255,65]`, `jax [0,120,255]`, default `[255,255,255]`.
- **Deferral signal:** wait on the **voice media player** leaving `playing`, NOT the satellite `responding` state (firmware blips `responding→idle→listening` mid-speech).
- **Flag ordering:** `set_cube_lights` sets `cube_light_command_this_turn` ON as its **first** action, before waiting or painting.
- **Overlay never invents a color** — it only changes brightness/effect on whatever the strips currently hold.
- **No automated test framework for HASS config.** Per-task gate = YAML parses (`ruby -ryaml`) + HASS config-check after deploy. Behavioral acceptance = live smoke (Task 4).
- **Effects (tunable on hardware):** pulse = `Breathe`; talk = `Gravcenter` (single-color, volume-reactive).

---

### Task 1: Persona color sync (head + body + ring)

Centralize the persona→color map into one script and have the Persona Switcher call it, so a persona switch turns the head + body strips and the Voice PE ring to the persona's signature color.

**Files:**
- Create: `data/homeassistant/scripts/lights/sync_lights_to_persona.yaml`
- Modify: `data/homeassistant/automations/persona/persona_switcher.yaml` (replace the inline ring `light.turn_on` step; optionally add a `homeassistant start` trigger)

**Interfaces:**
- Consumes: `input_select.current_persona`, the persona→RGB map (Global Constraints).
- Produces: script `script.sync_lights_to_persona` (no args) — sets head+body (solid, full bright) and the ring (rgb + full bright) to the current persona color. Called by Task-1's automation edit; safe to call manually.

- [ ] **Step 1: Create the `sync_lights_to_persona` script**

Create `data/homeassistant/scripts/lights/sync_lights_to_persona.yaml`:

```yaml
# --- Persona color sync ------------------------------------------------------
# The ONE place the persona->RGB map lives now (previously duplicated in the
# Persona Switcher automation's ring step). Applies the current persona's
# signature color to the cube's expressive lights: the head + body WLED strips
# (solid, full brightness) and the Voice PE LED ring (rgb + full brightness; the
# ring has its own effect set, so we don't send it a WLED effect name). The
# Persona Switcher automation calls this on every persona change. No scene/flag
# bookkeeping here — the next conversation turn's start-snapshot (cube_expression
# automation) captures whatever this leaves as that turn's resting base.
sync_lights_to_persona:
  alias: Sync Lights To Persona
  description: >-
    Set the head + body WLED strips (solid) and the Voice PE LED ring to the
    current persona's signature color at full brightness. Called by the Persona
    Switcher automation; safe to call manually to re-assert the persona look.
  sequence:
  - variables:
      rgb: >-
        {{ {'buddy': [255,220,0], 'neon': [255,0,128], 'zorp': [160,0,255],
            'crash': [0,255,65], 'jax': [0,120,255]}
           .get(states('input_select.current_persona'), [255,255,255]) }}
  - action: light.turn_on
    target:
      entity_id:
      - light.glitch_head_wled
      - light.cube_body_wled
    data:
      rgb_color: "{{ rgb }}"
      brightness: 255
      effect: Solid
  - action: light.turn_on
    target:
      entity_id: light.cube_cube_voice_led_ring
    data:
      rgb_color: "{{ rgb }}"
      brightness: 255
  mode: single
```

- [ ] **Step 2: Verify the script YAML parses**

Run:
```bash
cd /Users/estiens/code/glitchcube-main/glitchcube_rails
ruby -ryaml -e "YAML.load_file('data/homeassistant/scripts/lights/sync_lights_to_persona.yaml'); puts 'OK'"
```
Expected: prints `OK` (no exception).

- [ ] **Step 3: Edit the Persona Switcher automation to call the script**

In `data/homeassistant/automations/persona/persona_switcher.yaml`, replace the ring `light.turn_on` action (the `- action: light.turn_on` block targeting `light.cube_cube_voice_led_ring`) with a call to the new script, and add a `homeassistant start` trigger so a reboot re-asserts the persona look. The resulting `triggers:` and `actions:` sections read:

```yaml
  triggers:
  - trigger: state
    entity_id:
    - input_select.current_persona
  - trigger: homeassistant
    event: start
  conditions: []
  actions:
  - action: select.select_option
    target:
      entity_id: select.cube_cube_voice_assistant
    data:
      option: >-
        {{ {'buddy': 'Buddy', 'jax': 'Jax', 'neon': 'Neon', 'zorp': 'Zorp', 'crash': 'Crash'}
           .get(states('input_select.current_persona'), 'preferred') }}
  # Head + body strips + Voice PE ring -> persona signature color. The script owns the map.
  - action: script.sync_lights_to_persona
  # Govee top light — same signature color, solid. Internal-only (not exposed to Assist),
  # so this automation owns its idle look. Skip while the jukebox is playing so we don't
  # stomp the sound-reactive look (its own automation restores the color when playback stops).
  - if:
    - "{{ not is_state('media_player.jukebox_internal', 'playing') }}"
    then:
    - action: script.set_top_light_persona_color
  mode: single
```

Leave the `- id:`, `alias:`, and `description:` header lines above `triggers:` unchanged (optionally update the description prose to mention the script; not required).

- [ ] **Step 4: Verify the automation YAML parses**

Run:
```bash
ruby -ryaml -e "YAML.load_file('data/homeassistant/automations/persona/persona_switcher.yaml'); puts 'OK'"
```
Expected: prints `OK`.

- [ ] **Step 5: Commit**

```bash
git add data/homeassistant/scripts/lights/sync_lights_to_persona.yaml \
        data/homeassistant/automations/persona/persona_switcher.yaml
git commit -m "feat(hass): sync head/body/ring to persona color via sync_lights_to_persona"
```

---

### Task 2: Command deferral + turn flag

Add the `cube_light_command_this_turn` helper and make `set_cube_lights` claim the turn (flag first) and defer painting until the cube stops speaking.

**Files:**
- Modify: `data/homeassistant/packages/glitchcube_core.yaml` (add one `input_boolean`)
- Modify: `data/homeassistant/scripts/lights/cube_lights.yaml` (prepend flag + wait to `set_cube_lights` sequence)

**Interfaces:**
- Consumes: `media_player.cube_cube_voice_media_player` (wait signal).
- Produces: `input_boolean.cube_light_command_this_turn` — set ON by `set_cube_lights` the instant a command arrives; read by Task 3's turn-end handler; reset by Task 3 at turn start.

- [ ] **Step 1: Add the command flag helper**

In `data/homeassistant/packages/glitchcube_core.yaml`, under the existing `input_boolean:` mapping, add:

```yaml
  # Set ON (first action) by script.set_cube_lights the instant a brain light command
  # arrives; read at end-of-speech by the "Cube Expression" automation to decide
  # keep-the-new-look vs restore-the-pre-turn snapshot; reset OFF at each turn start.
  # Setting it BEFORE the deferral wait is deliberate: the turn-end restore and the
  # script's wait release on the SAME media-stop event, so the flag must already be set.
  cube_light_command_this_turn:
    name: "Cube light command landed this turn"
    initial: false
    icon: mdi:lightbulb-on-outline
```

- [ ] **Step 2: Verify the package YAML parses**

Run:
```bash
ruby -ryaml -e "YAML.load_file('data/homeassistant/packages/glitchcube_core.yaml'); puts 'OK'"
```
Expected: prints `OK`.

- [ ] **Step 3: Prepend the flag + deferral to `set_cube_lights`**

In `data/homeassistant/scripts/lights/cube_lights.yaml`, the `set_cube_lights` `sequence:` currently begins:

```yaml
  sequence:
  # Route the friendly both/head/body choice to the real WLED entities. `both` targets
  # them together so one call sets an identical look on head and body.
  - action: light.turn_on
```

Insert two actions between `sequence:` and that first `- action: light.turn_on`, so it becomes:

```yaml
  sequence:
  # Claim the turn FIRST (before the wait) so the same-edge end-of-speech restore in the
  # "Cube Expression" automation can never beat us to the flag: both that restore and the
  # wait below release on the SAME event (voice media leaving 'playing'). The action agent
  # calls this DURING the turn, so the flag is normally set seconds before end-of-speech.
  - action: input_boolean.turn_on
    target:
      entity_id: input_boolean.cube_light_command_this_turn
  # Hold the light change until the cube stops speaking so it doesn't stomp the "talking"
  # effect. Key off the VOICE media player, not the satellite 'responding' state — the
  # firmware blips responding->idle->listening mid-speech, which would release too early.
  # Outside a conversation the media player isn't playing, so this passes through instantly.
  - wait_template: "{{ not is_state('media_player.cube_cube_voice_media_player', 'playing') }}"
    timeout: "00:00:25"
    continue_on_timeout: true
  # Route the friendly both/head/body choice to the real WLED entities. `both` targets
  # them together so one call sets an identical look on head and body.
  - action: light.turn_on
```

Leave the rest of the sequence (the routing `light.turn_on`, its `data:` template, `mode: queued`, `max: 10`) unchanged.

- [ ] **Step 4: Verify the script YAML parses**

Run:
```bash
ruby -ryaml -e "YAML.load_file('data/homeassistant/scripts/lights/cube_lights.yaml'); puts 'OK'"
```
Expected: prints `OK`.

- [ ] **Step 5: Commit**

```bash
git add data/homeassistant/packages/glitchcube_core.yaml \
        data/homeassistant/scripts/lights/cube_lights.yaml
git commit -m "feat(hass): defer set_cube_lights past speech and claim the turn via flag"
```

---

### Task 3: Cube Expression automation

The core overlay: snapshot the resting look at genuine listening, brighten → Breathe → Gravcenter through the turn, and at end-of-speech restore the snapshot unless a command claimed the turn.

**Files:**
- Create: `data/homeassistant/automations/lights/cube_expression.yaml`

**Interfaces:**
- Consumes: `assist_satellite.cube_cube_voice_assist_satellite`, `media_player.cube_cube_voice_media_player`, `switch.cube_cube_voice_mute`, `input_boolean.persona_switching`, `input_boolean.cube_light_command_this_turn` (Task 2), head/body strips.
- Produces: `scene.before_conversation_turn` (created at each genuine listening); the live expression behavior. Terminal — no later task consumes its outputs.

- [ ] **Step 1: Create the automation**

Create `data/homeassistant/automations/lights/cube_expression.yaml`:

```yaml
- id: cube_expression_lighting
  alias: Cube Expression - head/body lights follow the turn
  description: >-
    Drives the head + body WLED strips through each conversation turn as an expressive
    overlay on WHATEVER color they currently hold (never imposes a color): genuine
    LISTENING brightens both to full ("just woke up"), PROCESSING gently pulses them
    (Breathe), RESPONDING runs a single-color volume-reactive effect (Gravcenter) so they
    pulse to the cube's own voice (the WLED controller's own always-on mic hears the room).
    At each genuine listening we snapshot the resting look into scene.before_conversation_turn;
    when the cube stops talking we either LEAVE the new look (if a brain set_cube_lights
    command claimed the turn via input_boolean.cube_light_command_this_turn) or RESTORE that
    snapshot. Reuses the mic-guard tells to reject the firmware's mid-speech
    responding->idle->listening blip: genuine listening = mic unmuted AND voice media not
    playing; true end-of-speech = the voice media player leaving 'playing'. All branches
    stand down while input_boolean.persona_switching is up (the grand-entrance show owns the
    lights). Effects (Breathe / Gravcenter) are tunable on hardware.
  triggers:
  - trigger: state
    entity_id: assist_satellite.cube_cube_voice_assist_satellite
    to: listening
    id: listening
  - trigger: state
    entity_id: assist_satellite.cube_cube_voice_assist_satellite
    to: processing
    id: processing
  - trigger: state
    entity_id: assist_satellite.cube_cube_voice_assist_satellite
    to: responding
    id: responding
  - trigger: state
    entity_id: media_player.cube_cube_voice_media_player
    from: playing
    id: tts_done
  - trigger: state
    entity_id: assist_satellite.cube_cube_voice_assist_satellite
    to: idle
    for: "00:00:10"
    id: ended
  # The show owns the lights during a grand entrance — stand down entirely while it's up.
  conditions:
  - "{{ is_state('input_boolean.persona_switching', 'off') }}"
  actions:
  - choose:
    # Genuine listening (NOT the mid-speech reopen blip): mic unmuted AND voice media not
    # playing. Snapshot the resting look FIRST (before the brighten), clear the command
    # flag for the new turn, then wake both strips to full brightness on their current color.
    - conditions:
      - "{{ trigger.id == 'listening' }}"
      - "{{ not is_state('media_player.cube_cube_voice_media_player', 'playing') }}"
      - "{{ is_state('switch.cube_cube_voice_mute', 'off') }}"
      sequence:
      - action: scene.create
        data:
          scene_id: before_conversation_turn
          snapshot_entities:
          - light.glitch_head_wled
          - light.cube_body_wled
      - action: input_boolean.turn_off
        target:
          entity_id: input_boolean.cube_light_command_this_turn
      - action: light.turn_on
        target:
          entity_id:
          - light.glitch_head_wled
          - light.cube_body_wled
        data:
          brightness_pct: 100
    # Thinking -> gentle Breathe pulse on the current color.
    - conditions:
      - "{{ trigger.id == 'processing' }}"
      sequence:
      - action: light.turn_on
        target:
          entity_id:
          - light.glitch_head_wled
          - light.cube_body_wled
        data:
          effect: Breathe
    # Speaking -> single-color volume-reactive effect; pulses to the cube's own voice.
    - conditions:
      - "{{ trigger.id == 'responding' }}"
      sequence:
      - action: light.turn_on
        target:
          entity_id:
          - light.glitch_head_wled
          - light.cube_body_wled
        data:
          effect: Gravcenter
    # True end of speech -> unless a command claimed the turn, restore the pre-turn look.
    # The 0.5s delay is insurance only; correctness rests on set_cube_lights setting the
    # flag upstream (first action). Guard the restore so a missing scene (e.g. speech with
    # no preceding listening) can't error.
    - conditions:
      - "{{ trigger.id == 'tts_done' }}"
      sequence:
      - delay: "00:00:00.5"
      - if:
        - "{{ is_state('input_boolean.cube_light_command_this_turn', 'off') }}"
        - "{{ states('scene.before_conversation_turn') not in ['unknown', 'unavailable'] }}"
        then:
        - action: scene.turn_on
          target:
            entity_id: scene.before_conversation_turn
    # Stuck-state safety: satellite idle 10s with nothing playing (e.g. TTS errored and
    # tts_done never fired) -> restore the pre-turn look and clear the flag.
    - conditions:
      - "{{ trigger.id == 'ended' }}"
      - "{{ not is_state('media_player.cube_cube_voice_media_player', 'playing') }}"
      - "{{ states('scene.before_conversation_turn') not in ['unknown', 'unavailable'] }}"
      sequence:
      - action: scene.turn_on
        target:
          entity_id: scene.before_conversation_turn
      - action: input_boolean.turn_off
        target:
          entity_id: input_boolean.cube_light_command_this_turn
  mode: queued
  max: 15
```

- [ ] **Step 2: Verify the automation YAML parses**

Run:
```bash
ruby -ryaml -e "YAML.load_file('data/homeassistant/automations/lights/cube_expression.yaml'); puts 'OK'"
```
Expected: prints `OK`.

- [ ] **Step 3: Commit**

```bash
git add data/homeassistant/automations/lights/cube_expression.yaml
git commit -m "feat(hass): add Cube Expression automation (wake/think/talk light overlay)"
```

---

### Task 4: Deploy + live smoke on dev HASS VM

There is no automated test for HASS behavior — this task is the behavioral acceptance. Deploy the config to the dev HASS VM (UTM, `root@glitch`), config-check, reload, and walk the spec's scenarios. Per the HASS config-sync workflow, `diff` before overwriting so a UI edit on the box isn't silently clobbered.

**Files:** none (deploy + verification only).

**Interfaces:**
- Consumes: everything from Tasks 1–3.
- Produces: a confirmed-working install + notes on the two hardware-tunable items (talk effect, scene-restore-of-a-running-effect).

- [ ] **Step 1: Diff local config against the box before deploying**

For each changed/new file, compare local vs box so a manual UI edit isn't lost:
```bash
for f in scripts/lights/sync_lights_to_persona.yaml \
         scripts/lights/cube_lights.yaml \
         automations/persona/persona_switcher.yaml \
         automations/lights/cube_expression.yaml \
         packages/glitchcube_core.yaml; do
  echo "=== $f ==="
  ssh root@glitch "cat /config/$f" 2>/dev/null | diff - "data/homeassistant/$f" || true
done
```
Expected: only your intended changes appear. Investigate any unexpected box-side content before overwriting.

- [ ] **Step 2: Copy the files to the box**

```bash
scp data/homeassistant/scripts/lights/sync_lights_to_persona.yaml root@glitch:/config/scripts/lights/
scp data/homeassistant/scripts/lights/cube_lights.yaml            root@glitch:/config/scripts/lights/
scp data/homeassistant/automations/persona/persona_switcher.yaml  root@glitch:/config/automations/persona/
scp data/homeassistant/automations/lights/cube_expression.yaml    root@glitch:/config/automations/lights/
scp data/homeassistant/packages/glitchcube_core.yaml              root@glitch:/config/packages/
```
Expected: all five transfer without error.

- [ ] **Step 3: Config-check, then reload**

```bash
ssh root@glitch "ha core check"
```
Expected: `Configuration check finished - no error found` (or equivalent success). If the `ha` CLI is unavailable on this VM, run **Developer Tools → YAML → Check Configuration** in the HASS UI instead.

Then reload without a full restart: HASS UI **Developer Tools → YAML** → reload **Scripts**, **Automations**, and **Input Booleans** (the new `input_boolean` needs an Input Boolean reload or a restart to register). If in doubt, restart Home Assistant.

- [ ] **Step 4: Smoke — persona sync**

Switch persona (HASS UI: set `input_select.current_persona`, e.g. to `jax`, or call `script.set_persona_quick`). Verify: head strip, body strip, and the Voice PE ring all turn to the persona color (jax = blue) at full brightness, solid.
Expected: all three match the persona color.

- [ ] **Step 5: Smoke — expression overlay (no command)**

Set a distinctive base first via the action tool (`script.set_cube_lights` with e.g. `led_strip: head, color: [255,0,0]` and again `led_strip: body, color: [128,0,255]`). Then start a conversation and watch the strips through the turn:
- LISTENING → both brighten to full on red / purple.
- PROCESSING → both Breathe-pulse on red / purple.
- RESPONDING → both run Gravcenter, pulsing to the cube's voice.
- End of speech (no light command in the reply) → both snap back to the resting red / purple.

Expected: the overlay never changes the hue; the strips return to red / purple after speech.

- [ ] **Step 6: Smoke — command replaces the base**

Have a conversation where the persona changes the lights (a reply that triggers a `set_cube_lights` command, e.g. "make everything deep blue"). Verify: the new look lands right as the cube stops talking and **persists** (no snap-back), and `input_boolean.cube_light_command_this_turn` shows `on` during the turn.
Expected: commanded look stays; on the following turn it is treated as the new resting base.

- [ ] **Step 7: Smoke — guards and safety**

- Trigger a grand entrance (`CubePersona.set_current_persona(persona, entrance: :grand)` from Rails, or raise `input_boolean.persona_switching`): confirm the expression automation stands down and the show owns the strips; normal expression resumes after the boolean drops.
- Confirm no `scene.turn_on` errors appear in the HASS log at boot/idle before the first conversation (the missing-scene guards hold).

Expected: no fighting during the show; no scene errors in the log.

- [ ] **Step 8: Record the two hardware-tunable outcomes**

Note in the smoke results: (a) whether `Gravcenter` reads well as the "talking" effect or another single-color volume-reactive effect (`Pixelwave` / `Puddlepeak` / `Gravfreq`) looks better; (b) whether `scene.turn_on` faithfully restores a **running effect** base (not just a solid color) on this WLED integration. If (b) fails, flag it — restore may need to also re-assert the effect explicitly.

- [ ] **Step 9: Commit any tuning changes**

If the smoke produced effect tweaks, apply them to the local YAML, re-run the relevant `ruby -ryaml` parse check, and commit:
```bash
git add data/homeassistant/automations/lights/cube_expression.yaml
git commit -m "tune(hass): dial in Cube Expression talk effect from hardware smoke"
```

---

## Self-Review

**Spec coverage:**
- Persona sync (head+body+ring) → Task 1. ✔
- Content-agnostic overlay (brighten/Breathe/Gravcenter on current color) → Task 3. ✔
- Snapshot at turn start / restore at end → Task 3 (listening + tts_done branches). ✔
- Deferral past speech (media-player signal) → Task 2. ✔
- Flag-first ordering to win the same-edge race → Task 2 (Step 3) + Task 3 (read). ✔
- Genuine-listening disambiguation, 10s-idle safety, persona_switching guard → Task 3. ✔
- Centralized color map → Task 1 (`sync_lights_to_persona`). ✔
- Hardware-tunable effect + scene-restore-of-effect → Task 4 Step 8. ✔
- Out of scope (top light, Rails) → untouched. ✔

**Placeholder scan:** No TBD/TODO; every YAML block is complete and copy-pasteable.

**Type/name consistency:** `input_boolean.cube_light_command_this_turn`, `scene.before_conversation_turn`, `script.sync_lights_to_persona`, and all device entity IDs are used identically across Tasks 1–4 and match the Global Constraints block.

**Note on missing-scene guard:** added beyond the spec (`states(...) not in ['unknown','unavailable']`) on both restore branches, because a dynamically-created scene genuinely does not exist before the first genuine listening (post-boot idle, or proactive speech with no listening) — restoring a non-existent scene would error. This is correctness for a real code path, not speculative defense.
