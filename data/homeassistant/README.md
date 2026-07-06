# Home Assistant config — the files we actually run

This mirrors the **GlitchCube-authored files that are live on the HASS box**
(`root@glitch.local:/config`) right now — not a full HASS config, just the parts we
own and maintain. Keep this in sync when you change config on the box.

Contents:
- `configuration.yaml` — the config root (enables `packages: !include_dir_named packages`
  and `template: !include_dir_merge_list templates/`).
- `automations.yaml`:
  - "Persona Switcher" — swaps the Assist pipeline when `input_select.current_persona`
    changes. Targets `select.cube_cube_voice_assistant` — the single live pipeline select
    on the "Cube Voice" device (a Home Assistant Voice PE, ESPHome-based; entity IDs were
    renamed from the `home_assistant_voice_09739d_*`/`square_voice` defaults to
    `cube_cube_voice_*`). Its firmware also exposes a `select.cube_cube_voice_assistant_2`
    sibling that isn't wired to anything active — don't target it. There's a second,
    unrelated "Square Voice" device in the registry — a stale Music Assistant-created
    shadow of the same physical speaker (`media_player.square_voice_2`,
    `button.square_voice_favorite_current_song`); harmless but not renamed.
  - "Cube Voice - Continuation Chime" — the Voice PE only plays its wake-word chime on a
    *local* wake-word detection; `continue_conversation` (server-driven, no local wake
    word) skips it, so the LED ring spins back into listening silently. This automation
    replays the chime for that case specifically, keyed on the assist satellite's
    `responding -> listening` transition (a fresh wake word is `idle -> listening`, so
    it doesn't double up). See `media/sounds/` below for the sound asset.
- `scripts.yaml` — HASS scripts exposed to the tool-calling HASS agent, e.g.
  `play_music_on_jukebox` (plays a track on `media_player.jukebox` via Music Assistant).
- `packages/` — our config packages:
  - `glitchcube_core.yaml` — input helpers Rails reads/writes (`input_select.current_persona`,
    `input_select.cube_mode`, host routing, etc.).
- `templates/` — plain YAML template-entity files, merged into the config root's single
  `template:` key via `!include_dir_merge_list` (each file is a bare list, no `template:`
  wrapper — see the comment in either file). These live outside `packages/` at the
  top level next to `automations.yaml`/`scripts.yaml` on request, **not** because it
  changes editability — YAML-defined template entities have no config entry, so they
  can't be assigned a device or edited via a GUI form either way (that's only possible
  for entities created through Settings → Devices & Services → Helpers → Template,
  a completely different, non-YAML storage mechanism we deliberately don't use here).
  - `glitchcube_world_state.yaml` — the composite **world-state template sensor**
    (`sensor.glitchcube_world_state`); its `content` attribute is injected into every
    persona prompt by `Prompts::ContextBuilder`. Extend this template as devices come
    online — no Rails change needed.
  - `glitchcube_cube_state.yaml` — trigger-based template sensor (`sensor.cube_state`)
    holding the brain's own turn output (`speech`, `inner_monologue` attributes) for
    display. Updated by `CubeStateUpdateJob` firing the `glitchcube_cube_state_update`
    event each turn — the opposite direction from world-state (this is read OUT of
    the brain, not INTO it).
- `custom_components/glitchcube_conversation/` — the custom HASS conversation
  integration that proxies visitor speech to the Rails `/api/v1/conversation` endpoint.
- `media/sounds/` — audio assets played via `media_player.play_media` with a
  `media-source://media_source/local/...` content ID (e.g. the continuation chime,
  `wake_word_triggered.flac`, pulled straight from the [Voice PE firmware's own sound
  assets](https://github.com/esphome/home-assistant-voice-pe/tree/dev/sounds) so it's
  the exact same chime). **Gotcha:** this deploys to the HAOS top-level `/media`
  directory, a separate bind mount from `/config` — NOT `/config/media` (that path
  looks plausible but Core never reads it; `media-source://media_source/local/...`
  resolves to `/media` on the host). Confirmed via `homeassistant.components.esphome
  .ffmpeg_proxy` logging a 404 against `/media/local/...` when the file was in the
  wrong place.

## Deploying a change to the box

```
sshpass -e scp <file> root@glitch.local:/config/<path>     # SSHPASS=easytoremember
# validate BEFORE reloading:  POST /api/config/core/check_config  (needs the long-lived token)
# then reload — a NEW template/integration needs a core restart:
#   POST /api/services/homeassistant/restart

# local media (media/sounds/*) deploys to a DIFFERENT root — not /config:
sshpass -e scp <file> root@glitch.local:/media/sounds/<path>
```

## Not this: `deprecated/homeassistant/`

That is an **old, drifted grab-bag snapshot** of a much larger HASS config from the
pre-amnesiacube era — reference only, not what runs today. This `data/homeassistant/`
is the curated, current truth.
