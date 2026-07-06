# Home Assistant config — the files we actually run

This mirrors the **GlitchCube-authored files that are live on the HASS box**
(`root@glitch.local:/config`) right now — not a full HASS config, just the parts we
own and maintain. Keep this in sync when you change config on the box.

Contents:
- `configuration.yaml` — the config root (enables `packages: !include_dir_named packages`).
- `automations.yaml` — the "Persona Switcher" automation (swaps the Assist pipeline
  when `input_select.current_persona` changes).
- `packages/` — our config packages:
  - `glitchcube_core.yaml` — input helpers Rails reads/writes (`input_select.current_persona`,
    `input_select.cube_mode`, host routing, etc.).
  - `glitchcube_helpers.yaml` — additional input helpers.
  - `glitchcube_world_state.yaml` — the composite **world-state template sensor**
    (`sensor.glitchcube_world_state`); its `content` attribute is injected into every
    persona prompt by `Prompts::ContextBuilder`. Extend this template as devices come
    online — no Rails change needed.
- `custom_components/glitchcube_conversation/` — the custom HASS conversation
  integration that proxies visitor speech to the Rails `/api/v1/conversation` endpoint.

## Deploying a change to the box

```
sshpass -e scp <file> root@glitch.local:/config/<path>     # SSHPASS=easytoremember
# validate BEFORE reloading:  POST /api/config/core/check_config  (needs the long-lived token)
# then reload — a NEW template/integration needs a core restart:
#   POST /api/services/homeassistant/restart
```

## Not this: `deprecated/homeassistant/`

That is an **old, drifted grab-bag snapshot** of a much larger HASS config from the
pre-amnesiacube era — reference only, not what runs today. This `data/homeassistant/`
is the curated, current truth.
