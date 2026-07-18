# TO BE DONE — Lakes of Fire final night (Sat July 18, 2026)

Everything code-side is already committed to this repo. This file is the **when-prod-and-HASS-are-back-up** checklist: deploy steps, on-device verification, the couple of things that need the physical AWTRIX / a live agent-prompt paste, plus the one change (T12) that still needs design + on-device iteration.

Repo is canonical: **scp `data/homeassistant/**` over the box and clobber**, then reload. Deploy Rails as usual.

---

## 0. Deploy

- [ ] Deploy Rails (context/prompt/show changes: T5, T6, T7, T11).
- [ ] `scp` all of `data/homeassistant/` to the box `/config` (clobber). Deleted files to make sure are GONE on the box:
  - `automations/idle/glitch_ambient.yaml`
  - `automations/presence/announce_nudge.yaml`, `automations/presence/marquee_nudge.yaml` (whole `presence/` dir)
- [ ] Reload HASS (YAML: `Developer Tools → YAML → Automations` + `Scripts`, or restart).
- [ ] `input_boolean.presence_nudge_enabled` was removed from `glitchcube_core.yaml` — after reload it should no longer exist. Remove it from any Lovelace dashboard that references it (`lovelace/cube_dev.storage.json` references it; harmless but stale).

---

## 1. Camera (T1) — no code, verify

- Camera capture is disabled at the pipeline: `input_boolean.disable_camera` now defaults **ON** (`initial: true`). `CameraDescriptionJob` checks it and skips; `input_text.current_camera_state` stays blank so nothing is injected into the brain prompt.
- [ ] After HASS boot, confirm `disable_camera` is ON.
- [ ] To re-enable later (better lighting), just flip it OFF — no redeploy.

## 2. Presence sensor (T2) — no code

- `binary_sensor.presence_sensor` will read `unavailable`. Nothing depends on it anymore (both presence automations were deleted). No action.

---

## 3. AWTRIX wake-hint app (T3) — DEVICE VERIFY

The wake hint moved off a repeating notification and onto the sign as a **second always-on app** the device cycles with the idle effect (idle effect ↔ wake hint, ~30s toggle). Notifications still override both.

- [ ] After scp+reload, run **`script.awtrix_install_idle_apps`** ONCE (Developer Tools → Actions). It publishes `marquee/settings {"ATRANS": true, "ATIME": 30000}` and seeds both `marquee/custom/idle` and `marquee/custom/wakehint`.
- [ ] Watch the sign for ~2 min: confirm it **toggles** between the random ambient idle effect and the wake-hint text roughly every 30s.
- [ ] Confirm the wake-hint text **varies** over a few minutes (the `wakehint_cycle` automation re-rolls the phrase every 1 min).
- [ ] Confirm a persona marquee message (talk to the cube) and the THINKING/LISTENING status still **override** both apps and then return to the loop.
- [ ] **Tune if needed** (device-specific, can't verify off-box):
  - If the 30s toggle feels wrong, adjust `ATIME` in the seed, or set a per-app `duration` in `set_marquee_idle` / `set_marquee_wakehint` payloads.
  - If the wake-hint text is hard to read (dim), the idle BRI may be low — bump brightness in `set_marquee_idle`/settings, or add a `BRI` to the wakehint publish.
  - AWTRIX firmware detail to confirm: a custom app with no `duration` honors global `ATIME`. If it instead switches after one scroll, add `"duration": 30` to the wakehint payload in `scripts/marquee/marquee.yaml → set_marquee_wakehint`.

---

## 8. Idle attention ping / chime_tts (T8) — DEVICE VERIFY

New: `automations/audio/idle_attention_ping.yaml` + `scripts/audio/attention.yaml`. Every 3 min while idle 3 min → 1/3 persona voiced call-out (chime_tts pre-SFX + line, current persona voice), 2/3 a bare attention SFX. **Plays out `media_player.cube_cube_voice_media_player` (the cube's own speaker), per the operator's explicit choice.**

- [ ] Confirm the SFX files exist on the box at **`/media/sounds/effects/`**: `bell_ding.mp3, cowbell.mp3, cymbal_crash.mp3, rooster.mp3, whistle.mp3, wind_chime.mp3, alarm_clock.mp3, cash_register.mp3` (the same set the retired `play_sound_effect` used). They're in the repo at `data/homeassistant/media/sounds/effects/` if the box is missing them.
- [ ] **chime_tts param shape** — verify `script.persona_attention_announce` actually speaks in the current persona's voice. It calls:
  ```yaml
  chime_tts.say:
    entity_id: media_player.cube_cube_voice_media_player
    chime_path: "/media/sounds/effects/<random>.mp3"
    message: "<line> Say 'Hey Glitch Cube' to wake me up."
    tts_platform: cloud
    language: "<en-NZ | en-US | ...>"
    options: { voice: "<MitchellNeural | GuyNeural | ...>" }
  ```
  If cloud voice selection doesn't take via `options.voice`, try `tld`/top-level `voice`, or the exact key your `chime_tts` version + the Nabu Casa cloud TTS expect. Persona→voice map (matches `lib/prompts/personas/*.yml voice_id`): buddy=GuyNeural/en-US, jax=MitchellNeural/en-NZ, neon=LibbyNeural/en-GB, zorp=PrabhatNeural/en-IN, crash=ConnorNeural/en-IE.
- [ ] **chime_path** — verify `/media/sounds/effects/x.mp3` resolves for `chime_tts` (absolute path). If not, use the path chime_tts expects on this box (may be `/media/local/...` or a `media-source://` — chime_tts docs vary by version).
- [ ] **SELF-WAKE RISK** — playing SFX/TTS out the VA speaker while the mic is open (idle) can make the cube hear itself and wake / self-STT. Watch during test. If it self-triggers: either (a) briefly mute `switch.cube_cube_voice_mute` around the ping, or (b) move these to the jukebox speaker (`media_player.jukebox_internal`) like the old `play_sound_effect` did.
- [ ] **Body-light sparkle timing** — `persona_attention_announce` snapshots the body light, sets Sparkle, then restores after `chime_tts.say`. If `chime_tts.say` returns before playback finishes, the sparkle won't hold — add a `delay` before the `scene.turn_on` restore if you want it to bracket the whole line.
- [ ] Optional: the operator wanted a **trumpet** and a **gong** too. Drop `trumpet.mp3` / `gong.mp3` into `/media/sounds/effects/` (and `data/homeassistant/media/sounds/effects/` in the repo) and add them to the `sfx_pool` lists in `scripts/audio/attention.yaml` (two places).

---

## 9. Idle body-light reset (T9) — verify

New: `automations/lights/idle_body_light_reset.yaml`. Body WLED → full brightness + persona color + solid/pulse/chase, on 3-min idle, re-rolled every 5 min.

- [ ] After ~3 min idle, confirm the body strip snaps to a clean, full-brightness persona-colored look (and isn't left dim/sound-reactive).
- Note: harmlessly overlaps T8's sparkle-and-restore; the two may bobble the body light briefly on the same tick. Cosmetic, self-corrects. Leave unless it looks bad — then add a mutual condition.

---

## 10. Jukebox split (T10) — LIVE AGENT PROMPT PASTE + verify

Code: `scripts/audio/jukebox.yaml` now has **`play_song_on_jukebox`** (fixed 90, waits for TTS to finish, fades in) and **`play_mood_music_on_jukebox`** (fixed 60, immediate, fades in). The old `play_music_on_jukebox` is **deleted**. Volume field is gone from both.

- [ ] **Expose the two new scripts** to the jukebox agent (`conversation.glitchcube_jukebox_agent`) in HASS, and **un-expose** the deleted `play_music_on_jukebox`.
- [ ] **Paste the updated jukebox agent system prompt** into that agent's instructions in HASS — repo copy: `data/homeassistant/prompts/proposed_jukebox_agent.md` (now describes two tools, no volume choice). HASS doesn't read the repo; keep them in sync.
- [ ] **Paste the updated action agent prompt** into `conversation.default_hass_tools_agent` — repo copy: `lib/prompts/hass_action_agent.md` (jukebox bullets updated to the two tools).
- [ ] Verify the **fade** works: each play sets volume 0 then ramps to target over ~3s (6×0.5s `volume_set`). If Music Assistant's `volume_set` is laggy/janky and the ramp stutters, **just delete the `repeat:` fade block** in each script (operator said fade is optional).
- [ ] Verify the **song wait**: with the persona still speaking, `play_song_on_jukebox` should hold until TTS ends (up to 25s), then start. Mood music should start immediately.
- Note: `media_player.jukebox_internal` is still exposed, so the agent can still nudge volume directly (e.g. "crank it" above 90).

---

## 11. Grand entrance (T11) — Rails, verify on the night

Code done (`Shows::GrandEntrance`): waits for the outgoing persona's TTS to finish before cutting in, theme trimmed to **45s**, marquee shows **"PERSONA SWITCHING"** then a held **"GLITCHCUBE UNAVAILABLE MID TRANSITION"**.

- [ ] On a real switch, confirm it no longer stomps the previous persona mid-sentence, the song is ~45s, and both marquee messages show.

---

## 6 (optional). Hold-the-switch-for-a-goodbye — DESIGN, only if wanted

Done for tonight (prompt tune): premonition window widened to 5 min + made actionable ("say your goodbyes now"); the standing `continue_conversation` instruction now forces a goodbye + wake-hint whenever a persona ends a conversation.

If, after watching tonight, personas still don't say goodbye before a switch, the deeper fix:
- The switch fires on a random timer (`RandomPersonaJob`, every 5 min tick, 20–50 min interval) regardless of whether a conversation is active, and hard-cuts it.
- Option: before `CubePersona.set_random(entrance: :grand)` actually switches, check for an active `Conversation`. If one exists, **defer** the switch one tick and inject a strong "this is your final turn, say goodbye now" system message so the persona gets one clean closing turn; switch on the next tick. Bounded (max one deferral) so a never-ending conversation can't block rotation forever.
- Files: `app/jobs/recurring/persona/random_persona_job.rb`, `app/models/cube_persona.rb`.

---

## 12. Persona marquee persists until idle/listening (T12) — DESIGN + ON-DEVICE ITERATION

**Not implemented** — needs the box to iterate on the racy mic-guard/marquee interaction. This is the "it's weird that the AWTRIX idle screen reappears while the persona is still speaking" fix.

### Current behavior
- A persona sets a marquee via the action agent → `script.awtrix_marquee_message` publishes a `marquee/notify` notification with a `repeat` count. AWTRIX scrolls it `repeat` times, then **auto-dismisses back to the app loop** (idle effect / wake hint) — which is why the idle screen pops back while the persona is still talking.
- `automations/voice/mic_guard_and_marquee.yaml` already owns marquee status: it dismisses on `responding` (so the persona's own marquee shows), sets THINKING on `processing`, LISTENING on the real playback-end unmute.

### Proposed change (to iterate on-device)
- When a persona sets a marquee **during a turn**, publish it as a **held** notification (`"hold": true`, no self-dismiss) instead of a repeat-then-dismiss one — so it stays up through the whole spoken response.
  - Concretely: give `awtrix_marquee_message` a `hold` option that publishes `{"text": ..., "hold": true, ...}` (AWTRIX holds a notification with `hold:true` until explicitly dismissed), and have the action-agent path use it for persona marquees.
- **Clear it when the satellite flips to `idle` OR `listening`** (the turn is over / it's the visitor's turn) — add those to the mic-guard automation's dismiss paths (`marquee/notify/dismiss`). Today mic-guard dismisses on `responding` and on the 10s-idle safety; extend it to dismiss the held persona marquee on the `listening` transition and the real idle.
- **Edge case the operator is OK leaving for last:** if a persona sets NO marquee in a turn, the app loop (idle effect / wake hint) keeps showing while it speaks — including possibly the "say Hey Glitchcube" hint mid-response. Acceptable for now.

### Why it needs the box
- AWTRIX `hold:true` / dismiss semantics and stacking, plus the firmware's `responding→idle→listening` blips (documented in the mic-guard header), make this timing-sensitive — it has to be watched live to avoid clearing too early (idle screen flashes back) or too late (stale marquee lingers into the next turn).

---

## Quick sanity list after everything's up
- [ ] Talk to the cube → persona responds, sets lights/marquee, ends with a goodbye + "Hey Glitch Cube" hint when it stops.
- [ ] Leave it idle 3+ min → attention pings fire (SFX / persona call-out); body light resets clean; AWTRIX toggles idle-effect ↔ wake-hint.
- [ ] Trigger a persona switch → outgoing persona finishes speaking, 45s theme, two marquee messages, new persona arrives.
- [ ] Ask for "a song" vs "background music" → correct tool, correct volume (90 vs 60), fades in.
