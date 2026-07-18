# Lakes of Fire final night — change set (2026-07-18)

Tactical changes for the last night of the burn. Operator-driven; each change was reviewed
via pal → deepseek-v4-pro before landing. Forward-looking / device-dependent work lives in
[`TO_BE_DONE_STILL_JULY_18.md`](../../../TO_BE_DONE_STILL_JULY_18.md) at the repo root.

## Decisions
- **T6 goodbyes:** prompt/window tune now (not tied to round count — the switch is a random
  timer). Deeper "hold the switch for a goodbye turn" deferred to TO_BE_DONE for the operator
  to green-light after seeing tonight.
- **T8 attention:** use `chime_tts` (installed) with a random `/media/sounds/effects/*` pre-SFX
  + the current persona's cloud voice; play out the cube's own VA speaker (operator's explicit
  choice, self-wake risk noted).
- **T1 camera:** default `disable_camera` ON for the event.
- **T10 jukebox:** replace the single volume-parameterized play tool with two (song / mood),
  volume hardcoded + faded in.

## What changed (all in this repo)

### Rails
- `app/services/prompts/context_builder.rb` — T5 event-note block (always-on); T6 premonition
  window 3→5 min + actionable "say goodbyes now"; doc-comment updates.
- `lib/prompts/general/end_system_prompt.txt` — T6 standing rule: any `continue_conversation:
  false` turn MUST speak a goodbye + "Hey Glitch Cube" wake hint.
- `lib/prompts/personas/jax.yml` — T7 Kessler / frozen-wasteland backstory + regulars Trent & Boyd.
- `app/services/shows/grand_entrance.rb` — T11 wait for outgoing TTS to finish, theme 60→45s,
  "PERSONA SWITCHING" → held "GLITCHCUBE UNAVAILABLE MID TRANSITION" marquee.
- `lib/prompts/hass_action_agent.md` — T10 jukebox bullets → two tools.
- Specs updated: `spec/services/shows/grand_entrance_spec.rb`, `spec/services/prompts/context_builder_spec.rb`.

### HASS (`data/homeassistant/`) — canonical; scp+clobber to deploy
- **Deleted:** `automations/idle/glitch_ambient.yaml` (T4), `automations/presence/{announce,marquee}_nudge.yaml` (T3).
- **`packages/glitchcube_core.yaml`** — removed `presence_nudge_enabled`; `disable_camera` initial ON (T1).
- **`scripts/marquee/marquee.yaml`** — T3: new `set_marquee_wakehint` app; seed now sets
  `ATRANS:true`/`ATIME:30` (ATIME is SECONDS on fw 0.98, not ms) and seeds two always-on apps (idle effect + wake hint) the device cycles.
- **`automations/marquee/wakehint_cycle.yaml`** — T3: re-roll the wake-hint phrase every 1 min.
- **`scripts/audio/attention.yaml`** + **`automations/audio/idle_attention_ping.yaml`** — T8.
- **`automations/lights/idle_body_light_reset.yaml`** — T9.
- **`scripts/audio/jukebox.yaml`** — T10 two play scripts, volume hardcoded + faded.
- **`prompts/proposed_jukebox_agent.md`** — T10 two-tool prompt (paste into live agent).
- **`README.md`** — kept in sync.

## Still open (see TO_BE_DONE)
- T3 AWTRIX device verification (ATRANS/ATIME rotation, notification override, readability).
- T8 chime_tts param/voice/chime_path verification + self-wake watch; optional trumpet/gong SFX.
- T10 paste agent prompts into HASS, expose the two scripts, verify fade.
- T6 optional hold-for-goodbye (design in TO_BE_DONE).
- **T12** persona-marquee-persists-until-idle/listening — design in TO_BE_DONE; needs on-device iteration.
