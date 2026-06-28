# Deprecated — Home Assistant config snapshots

These are **reference snapshots**, not live config. Rails never loads anything in
here — they're kept around because some of them are still useful to copy from when
configuring a HASS instance (sensors, templates, scripts, dashboards, automations).

The live HASS config lives on the actual Home Assistant box (the UTM VM in dev —
`glitch.local`, SSH `root` / `easytoremember`). This in-repo copy drifted from the
live instance long ago; treat it as a grab-bag of examples, not a source of truth.

## What's here

- `homeassistant/` — full snapshot of an old HASS config dir: automations, scripts,
  sensors, templates, dashboards, blueprints, AWTRIX apps, Frigate, GPS sensors, etc.
  Lots of it is Burning Man / old-architecture specific and won't be reused as-is.
- `config_home_assistant/` — was `config/home_assistant/`; held `proactive_conversation.yaml`.
- `gps_scene_creator_automation.yaml` — was a stray HASS automation file living in
  `app/services/gps/` (the "Cube Voice — Scene Creator" voice automation).

## If you need one of these

Copy the relevant file to the live HASS box and adapt it. Don't wire Rails to read
from this directory — the Rails ↔ HASS contract is the REST/event API, not shared files.
