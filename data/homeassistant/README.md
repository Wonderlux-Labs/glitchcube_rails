# Home Assistant config — the files we actually run

This mirrors the **GlitchCube-authored files that are live on the HASS box**
(`root@glitch.local:/config`) — not a full HASS config, just the parts we own.
The repo is **canonical**: deploy by scp'ing this tree over (see the bottom).
Keep this inventory in sync when you add/remove an automation, script, or helper.

Box-only files NOT tracked here (never overwrite/delete them): `secrets.yaml`,
`scenes.yaml`, `.storage/`, the HA database.

## Layout (`configuration.yaml` includes)

| Key | Include | Where |
|---|---|---|
| `automation:` | `!include_dir_merge_list automations/` | one automation per file, in `<domain>/` folders |
| `script:` | `!include_dir_merge_named scripts/` | scripts grouped by topic per file (named dict — NOT a list) |
| `template:` | `!include_dir_merge_list templates/` | template sensors |
| `homeassistant.packages:` | `!include_dir_named packages/` | input helpers + rest_commands |
| `scene:` | `!include scenes.yaml` | **box-only**, not in this repo |

Automations keep an `id:` and their `alias:`, so entity_ids / unique_ids (and
therefore Assist exposure, areas, and registry settings) are stable across the
split. Automations call scripts by `script.<slug>` at runtime — file location is
irrelevant to that.

## Automations — `automations/<domain>/` (10)

**persona/**
- `persona_switcher.yaml` — on `input_select.current_persona` change: swap the Assist
  TTS pipeline on the Cube Voice device and call `script.sync_lights_to_persona` (body
  WLED strip + Voice PE LED ring to the persona's signature color).
- `switching_silence.yaml` — while `input_boolean.persona_switching` is up (a Rails
  grand-entrance show), mute the mic + stop media; unmute when it drops.

**voice/**
- `mic_guard_and_marquee.yaml` — self-STT fix (mute on `responding`, unmute on real
  playback end) plus the LISTENING/THINKING marquee status labels.

**marquee/**
- `idle_effect_cycle.yaml` — every ~2 min, pick a random idle effect for the AWTRIX sign.

**camera/**
- `clear_stale_description.yaml` — blank `input_text.current_camera_state` after ~3 min so a stale look never lingers.

**audio/**
- `quiet_mode_autoduck_jukebox.yaml` — while `input_boolean.quiet_mode` is on, cap
  `media_player.jukebox_internal` at `input_number.quiet_mode_max_volume`.

**lights/**
- `top_light_turn_indicator_blink_test.yaml` — diagnostic: blink the Govee top light on listening/processing (gated by `input_boolean.top_light_turn_indicator`).

**presence/**
- `nudge_when_idle.yaml` — when someone lingers without starting a conversation, nudge them (marquee hint + persona voice call-out). Gated by `input_boolean.presence_nudge_enabled`.

**connectivity/** — internet-outage "resting" mode (see the spec at
`docs/superpowers/specs/2026-07-14-internet-outage-resting-mode-design.md`)
- `internet_down_enter_rest.yaml` — `binary_sensor.internet` off 5 min → `script.enter_rest_mode` (+ a `/5` re-assert while still down).
- `internet_up_wake_from_rest.yaml` — `binary_sensor.internet` on 3 min while resting → `script.wake_from_rest`.

## Scripts — `scripts/<domain>/` (13)

**audio/**
- `jukebox.yaml` — `play_music_on_jukebox` (play a track/query, volume-aware), `search_jukebox` (search the library).

**marquee/** — `marquee.yaml`
- `awtrix_marquee_message` — flash a message (color/rainbow/duration) on the LED sign.
- `awtrix_marquee_restore_brightness` — restore the idle BRI (helper).
- `awtrix_marquee_clear` — dismiss the current message.
- `set_marquee_idle` — set the always-on idle screen (effect/palette/speed).
- `awtrix_install_idle_apps` — post-reflash seed (ATRANS off + baseline idle).

**lights/**
- `cube_lights.yaml` — `set_cube_lights`: the Assist-facing control for the single body
  WLED strip (color/brightness/effect; many sound-reactive). The old head strip is
  unused/unexposed — the head cube is the Voice PE's firmware-controlled LED ring, which
  runs its own listening/processing effects (no HASS expression automations anymore).
- `top_light.yaml` — `set_top_light_persona_color` (dim persona-color ambient glow), `set_top_light_effect` (a preset Govee scene).

**persona/** — `persona.yaml`
- `set_persona_quick` — fanfare-free persona switch (dev/Assist).

**connectivity/** — `rest_mode.yaml`
- `enter_rest_mode` — sleep the cube during an outage: dim-red lights, muted mic, stopped media, `low_power`, held "RESTING" marquee. Idempotent.
- `wake_from_rest` — wake after the outage: clear the sign, back to `conversation`, fire `rest_command.glitchcube_grand_entrance` (which resyncs lights, plays a song, announces arrival, un-mutes).

## Input helpers & rest_commands — `packages/`

Input helpers stay in packages (they're finicky when split into include-dirs).

- `glitchcube_core.yaml`
  - `input_select`: `current_persona`; `cube_mode` (**currently unused** — set by rest mode as a status flag, nothing reads it).
  - `input_text`: `glitchcube_host` (Rails host:port), `backend_health_status`,
    `marquee_text`, `current_camera_state`; `glitchcube_breaking_news` (**currently unused**).
  - `input_boolean`: `usb_charger`, `strobe_light`, `top_light_turn_indicator`,
    `presence_nudge_enabled`, `disable_camera`, `persona_switching`, `quiet_mode`,
    **`internet_resting`** (cube asleep/offline — set by the rest-mode scripts).
  - `input_number`: `quiet_mode_max_volume`. `input_button`: `trigger_alarm`.

  (Dev-mock helpers `dev_jukebox_song` / `dev_mood_music` / `dev_sound_effect` /
  `announcement` and the `loudspeaker_announcement` dev script were removed.)
- `cube_screen.yaml` — M5Stack Core2 display helpers (`input_text.m5_screen_text` /
  `_emoji` / `_color`); entity_ids the ESPHome `cube-screen` firmware subscribes to.
- `glitchcube_rails_triggers.yaml` — HASS→Rails `rest_command`s, all hitting the one
  `Api::V1::HomeAssistantWebhookController` (`/api/v1/hass/*`):
  - `glitchcube_play_theme_song` → `/api/v1/hass/theme_song`
  - `glitchcube_grand_entrance` → `/api/v1/hass/grand_entrance`
  - `glitchcube_glitch_short` → `/api/v1/hass/glitch_short` (`Shows::GlitchShort`: one short glitch-radio stab + WLED spasm)
  - `glitchcube_glitch_long` → `/api/v1/hass/glitch_long` (`Shows::GlitchLong`: long bed → short stab → long bed, ~45-85s)

**Connectivity signal:** `binary_sensor.internet` is the built-in HASS `ping`
integration (configured in the UI, not YAML) — the rest-mode automations trigger off it.

## Templates — `templates/` (2)

- `glitchcube_world_state.yaml` — `sensor.glitchcube_world_state`; its `content` is
  injected into every persona prompt by `Prompts::ContextBuilder`. Extend as devices
  come online, no Rails change needed.
- `glitchcube_cube_state.yaml` — trigger-based `sensor.cube_state` holding the brain's
  own turn output (`speech`, `inner_monologue`) for display; updated by `CubeStateUpdateJob`.

## Custom component & media

- `custom_components/glitchcube_conversation/` — the custom conversation integration that
  proxies visitor speech to Rails `/api/v1/conversation`.
- `media/sounds/` — audio assets played via `media_player.play_media`
  (`media-source://media_source/local/...`). **Gotcha:** these deploy to the HAOS
  top-level `/media` mount, NOT `/config/media` (Core never reads the latter).

Theme songs are NOT here — they live in `data/rails_media/theme_songs/` (outside this
tree), played by Rails off the host speaker (`HostAudio` / `Shows::GrandEntrance`). Never
scp them to the box.

## Deploying to the box (repo is canonical)

```bash
# from data/homeassistant/ — push the config the box loads:
sshpass -p easytoremember scp -r configuration.yaml automations scripts packages templates \
  root@glitch.local:/config/
# reorg gotcha: if the box still has old monolith automations.yaml/scripts.yaml, delete them:
sshpass -p easytoremember ssh root@glitch.local 'rm -f /config/automations.yaml /config/scripts.yaml'
# validate, then apply (a structural/include or new-helper change needs a restart):
sshpass -p easytoremember ssh root@glitch.local 'ha core check && ha core restart'
# media/sounds/* deploy to a DIFFERENT root:
sshpass -p easytoremember scp media/sounds/<f> root@glitch.local:/media/sounds/
```

Removing an automation/script from the repo leaves an orphaned `unavailable` entity in
the box's registry (harmless; bulk-delete in the HA UI if you want it tidy).

## Not this: `deprecated/homeassistant/`

An old, drifted snapshot of a much larger pre-amnesiacube config — reference only. This
`data/homeassistant/` tree is the current truth.
