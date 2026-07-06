# Deprecated — CubeData / HaDataSync sensor-registry layer

An unfinished "centralized HomeAssistant data management" abstraction from the
pre-amnesiacube era. Rails never loads anything in here — it lives outside `app/`
and `config/`, so Zeitwerk and the initializer loader both ignore it. Kept as
browsable reference in case we want to rebuild something like it as more devices
come online, not as live code.

## What this was

- `app/models/cube_data.rb` + `app/models/cube_data/*.rb` — `CubeData`, meant to
  replace `HaDataSync` with a single source of truth for sensor entity IDs
  (`CUBE_SENSORS`), a caching `read_sensor`/`write_sensor` layer, and per-domain
  submodules (`Lights`, `Persona`, `Mode`, `System`, `Conversation`, `Memory`,
  `Events`, `Tools`, `WorldState`, `Location`, `Adapters`).
- `app/models/ha_data_sync.rb` (`HaDataSync`) — the older, simpler version it was
  meant to replace: one-off `update_*`/`get_*` methods pushing state to specific
  HA sensors (backend health, deployment status, conversation status, memory
  stats, persona details, breaking news, etc).
- `config/initializers/cube_data.rb` — called `CubeData.initialize!` on every
  boot (module autoload + prod cache warm). This ran, but nothing downstream
  ever called into `CubeData` from a live request/job/controller path.

## Why it's here instead of live

Neither class had any caller left in `app/controllers`, `app/services`, or
`app/jobs` by the time of the amnesiacube/HASS-agent refactors — most of the
sensors they reference (`sensor.persona_details`, `sensor.glitchcube_memory_stats`,
`sensor.world_state`, etc.) were tied to memory/summarizer/tool-calling systems
that have since been removed or replaced (see the root `CLAUDE.md`). The
initializer ran harmlessly every boot but did nothing anyone depended on.

## If you pick this back up

`CubeData::CUBE_SENSORS` is a reasonable map of "every sensor we might want" —
useful as a checklist when reintroducing sensors, but verify each entity_id
still matches what's live on the HASS box (`data/homeassistant/`) before trusting
it; several (e.g. `sensor.world_state`, `sensor.persona_details`) no longer exist.
