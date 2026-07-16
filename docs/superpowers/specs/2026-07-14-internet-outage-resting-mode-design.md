# Internet-outage "Resting" mode + smarter persona rotation

**Date:** 2026-07-14
**Status:** Approved design

## Problem

Without internet the cube can't reach its cloud LLMs, so it can't really do
anything. Rather than sit there broken (and burn battery), it should notice the
outage, go quietly to sleep with a "come back later" sign, and wake itself back
up with a fresh persona's grand entrance when connectivity returns.

Two independent pieces:

1. **HASS**: a connectivity sensor + enter-rest / wake-from-rest orchestration.
2. **Rails**: a wake endpoint, plus smarter `set_random` so waking never picks the
   dominant persona or the one that just left.

## Part 1 — HASS connectivity + rest/wake

### Connectivity sensor + flag — `packages/glitchcube_connectivity.yaml`

- **`binary_sensor.internet`** — the built-in HASS `ping` integration (configured
  in the UI, not YAML), `on` when the internet is reachable. The automations
  trigger off it directly. (An earlier draft shipped a `command_line` ping sensor;
  dropped in favor of the native integration.)
- `input_boolean.internet_resting` — marks that we're in rest mode. Gates both
  automations so they can't double-fire, and is the flag the wake path keys off.
  This is the only thing the package now defines.

### Enter rest — `script.enter_rest_mode` + automation

**Automation `internet_down_enter_rest`:** triggers when Internet Connection is
`off` **for 5 minutes**; also a `time_pattern` `/5` re-assert tick while it stays
off (this is the "repeating" that survives a marquee power-cycle). Condition:
fire the enter script regardless (idempotent), but only *log/announce* fresh
entry when `internet_resting` was off.

**`script.enter_rest_mode`** (idempotent):
1. `input_boolean.internet_resting` → on; `input_select.cube_mode` → `low_power`.
2. Mute mic: `switch.turn_on switch.cube_cube_voice_mute`.
3. Stop media: `media_player.media_stop` on `media_player.jukebox_internal` and
   `media_player.cube_cube_voice_media_player`.
4. Lights → dim red (battery-light):
   - `script.set_cube_lights` — `led_strip: both`, `color: [255,0,0]`,
     `brightness: 25`, `effect: Solid`.
   - Top light: `switch.turn_off switch.cube_light_music_mode` first (existing
     revert rule), then `light.turn_on light.top_light` `rgb_color: [255,0,0]`,
     `brightness: 64` (~25%).
5. Marquee → held red message: publish `marquee/settings` `{"BRI": 30}` (dim),
   then `marquee/notify` with
   `{"text":"THE GLITCHCUBE IS CURRENTLY RESTING - PLEASE CHECK BACK LATER",
   "hold": true, "color": "#FF0000"}`. `hold:true` holds until dismissed; the
   2-min idle-cycle only touches the background app underneath, so it won't fight
   the message.

### Wake from rest — `script.wake_from_rest` + automation

**Automation `internet_up_wake_from_rest`:** triggers when Internet Connection is
`on` **for 3 minutes** AND `internet_resting` is on.

**`script.wake_from_rest`:**
1. Dismiss marquee (`marquee/notify/dismiss`); restore normal brightness
   `marquee/settings` `{"BRI": 150}`; call `script.set_marquee_idle` for a fresh
   idle screen.
2. `input_select.cube_mode` → `conversation`; `input_boolean.internet_resting` → off.
3. Fire `rest_command.glitchcube_grand_entrance`.

The grand entrance owns everything else. Rails' `Shows::GrandEntrance` raises
`input_boolean.persona_switching`, runs the anomaly VO + lights, plays a theme
song, and delivers the arrival via `assist_satellite.start_conversation`. When it
ends, `persona_switching` drops and the existing
"Persona switching: silence during the show" automation **unmutes the mic**. So
the wake script deliberately does **not** unmute — the mic stays shut through the
show and the show un-mutes it. Lights get resynced by the entrance too.

### rest_command — `packages/glitchcube_rails_triggers.yaml` (append)

```yaml
  glitchcube_grand_entrance:
    url: >-
      http://{{ states('input_text.glitchcube_host') | trim }}{{ '' if ':' in states('input_text.glitchcube_host') else ':4567' }}/api/v1/persona/grand_entrance
    method: POST
    content_type: "application/json"
    payload: "{}"
```

### File placement note

The config was also reorganized into a directory-per-domain layout in this change:
`automation: !include_dir_merge_list automations/` and
`script: !include_dir_merge_named scripts/` (note the different directive —
scripts are a named dict, not a list). So the rest-mode pieces live at:
- `automations/connectivity/internet_down_enter_rest.yaml`,
  `automations/connectivity/internet_up_wake_from_rest.yaml`
- `scripts/connectivity/rest_mode.yaml` (`enter_rest_mode`, `wake_from_rest`)

Input helpers stay in `packages/` (they're finicky when split this way):
`input_boolean.internet_resting` lives in `packages/glitchcube_core.yaml`. The
`rest_command` lives in `packages/glitchcube_rails_triggers.yaml`.

## Part 2 — Rails: wake endpoint + smarter rotation

### Endpoint

HASS only ever had one Rails rest_command (`theme_song`). Rather than add a
per-action controller, consolidate all HASS→Rails triggers into one
`Api::V1::HomeAssistantWebhookController` (routed under `/api/v1/hass/*`) and
retire `AudioController`.

- `POST /api/v1/hass/theme_song` → `#theme_song` (moved verbatim from AudioController).
- `POST /api/v1/hass/grand_entrance` → `#grand_entrance` → `CubePersona.set_random(entrance: :grand)`,
  `render_api_success(enqueued: true)`. Fire-and-forget.
- The `glitchcube_play_theme_song` rest_command URL updates to the new path in
  the same change.

### Smarter `set_random`

Rotation must avoid (a) the persona **dominating** the cube and (b) the persona
from the **previous session**, so no one persona takes over and we never bounce
straight back to the one that just left. Exclude both from the active pool:
overlap → choose from 4, distinct → choose from 3. Never empty.

- **Dominant** = pool member with the most total turns, `SUM(message_count)`
  grouped by `Conversation.persona`. (There is no `conversation_rounds` column;
  summed `message_count` is the faithful "how much airtime" measure.) `nil` when
  there's no conversation data yet — then nothing is excluded on that axis.
- **Previous session** = most recent `persona`-type `Summary`'s persona slug
  (`Summary.persona.order(created_at: :desc).first&.persona&.slug`). `nil` before
  any persona summary exists.

```ruby
def self.set_random(entrance: :grand)
  set_current_persona(rotation_candidates.sample, entrance: entrance)
end

# Active pool minus the heaviest-talking persona and the previous session's
# persona. Overlap -> 4 candidates; distinct -> 3; never empty.
def self.rotation_candidates
  pool = Persona.active.pluck(:slug).map(&:to_sym)
  pool = PERSONAS if pool.empty?
  excluded = [most_talkative_persona(pool), previous_session_persona].compact.uniq
  (pool - excluded).presence || pool
end

def self.most_talkative_persona(pool)
  counts = Conversation.where.not(persona: nil).group(:persona).sum(:message_count)
  return nil if counts.empty?
  pool.select { |s| counts[s.to_s].to_i.positive? }.max_by { |s| counts[s.to_s].to_i }
end

def self.previous_session_persona
  Summary.persona.order(created_at: :desc).first&.persona&.slug&.to_sym
end
```

### Tests (`spec/models/cube_persona_spec.rb`)

`.rotation_candidates`:
- excludes the most-talkative persona (seed conversations with lopsided `message_count`)
- excludes the previous-session persona (seed a `persona` summary)
- overlap → 4 candidates; distinct → 3 candidates
- no data → all active personas eligible
- result is never empty

## Deployment

HASS files are scp'd to `glitch.local` and reloaded as usual (diff before
overwrite per the config-sync rule; HASS UI edits strip comments). Because the
config was restructured, the deploy now syncs the whole `automations/` and
`scripts/` trees plus `configuration.yaml` and `packages/`, not just two files —
and the theme_song rest_command URL moved to `/api/v1/hass/…`, so the HASS and
Rails sides must deploy together. Rails changes ship with the app.

## Out of scope / deliberately not done

- No extra safety-unmute in the wake path — the grand entrance owns the un-mute.
- No `ping` UI-integration (config-flow only, can't be scp'd) — YAML-native probe
  instead.
- No backward-compat shims. This is the current, correct behavior.
