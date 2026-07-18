# Automations & Scripts — context index

These live in the single files **`automations.yaml`** and **`scripts.yaml`** so they're
editable in the Home Assistant visual builder (Settings → Automations / Scripts). The UI
**rewrites the whole file and strips all comments** on save, so the per-item context that
used to live in YAML comments is preserved here instead, anchored by the stable
`id` / script slug (entity_ids never change → Assist exposure is untouched).

`line ~N` markers are a convenience snapshot. After you edit in the UI and `scp` the files
back into the repo, run `bin/reindex_context.rb` to refresh them.

## Automations (`automations.yaml`)

### audio

- **`cube_idle_attention_ping`** — Idle: attention ping (SFX / persona call-out) — _line ~2_
  <details><summary>context (idle_attention_ping.yaml)</summary>

  > 1-in-3 → full persona voiced call-out; otherwise just a sound effect.

  </details>
- **`jukebox_now_playing_marquee`** — Jukebox: NOW PLAYING marquee — _line ~30_
  <details><summary>context (now_playing_marquee.yaml)</summary>

  > Foreground volume only (mood 60 / song 90 both qualify; anything <= 50 stays silent).
  > Don't fight a persona: no announce during a switch or while a conversation is active.
  > Colored music-note icons on the AWTRIX device — one picked at random per announce.

  </details>
- **`quiet_mode_autoduck_jukebox`** — Quiet mode: auto-duck jukebox — _line ~77_

### camera

- **`camera_clear_stale_description`** — Camera: clear stale description — _line ~114_

### connectivity

- **`backend_restart_watchdog`** — Backend: last-resort restart when wedged too long — _line ~135_
  <details><summary>context (backend_restart_watchdog.yaml)</summary>

  > --- Backend wedged: last-resort restart -----------------------------------------
  > sensor.glitchcube_backend (templates/glitchcube_backend_health.yaml) reads "online"
  > only while Rails' once-a-minute heartbeat is < 3 min old, else UNAVAILABLE. That
  > heartbeat is written by a SolidQueue job, so it stops the moment the JOB workers
  > wedge — even while Puma is still answering HTTP. That specific state (jobs stuck /
  > backend degraded but the web thread alive) is both when a fresh boot helps AND when
  > the restart rest_command can still land, so it's the trigger here.
  > 15-min debounce so a normal reboot / HASS-VM restart / brief blip never trips it.
  > Rails throttles honored restarts (10-min cooldown that survives the reboot), so even
  > if this re-fires there's no boot loop. If Rails is FULLY down the rest_command just
  > fails harmlessly — this can only ever HELP or no-op, never make things worse.
  > NOTE: verify sensor.glitchcube_backend behaves as expected on the live box before
  > trusting this unattended — it was added without a running backend to test against.

  </details>
- **`internet_down_enter_rest`** — Internet down: enter rest mode — _line ~151_
  <details><summary>context (internet_down_enter_rest.yaml)</summary>

  > --- Internet outage: rest + wake ------------------------------------------------
  > The cube can't do anything without its cloud brain, so when the internet has been
  > down a while it goes to sleep (script.enter_rest_mode) and when it comes back it
  > wakes with a fresh persona's grand entrance (script.wake_from_rest). Sensor +
  > flag: packages/glitchcube_connectivity.yaml. Scripts: scripts.yaml. Design:
  > docs/superpowers/specs/2026-07-14-internet-outage-resting-mode-design.md.
  > Re-assert tick: keep the resting state fresh while the outage persists.
  > went_down = the real 5-min-offline edge (this is what INITIATES rest). The
  > periodic tick only RE-asserts an already-resting cube (still offline) so it
  > never short-circuits the 5-min debounce. enter_rest_mode is idempotent.

  </details>
- **`internet_up_wake_from_rest`** — Internet up: wake from rest mode — _line ~174_

### lights

- **`cube_idle_body_light_reset`** — Idle: reset body light to persona look — _line ~191_
  <details><summary>context (idle_body_light_reset.yaml)</summary>

  > First reset at 3 min idle, then a fresh look every 5 min while still idle.
  > 1 solid, 2 pulse, 3 chase/scan.

  </details>
- **`top_light_turn_indicator_blink_test`** — Top light: turn indicator (blink test) — _line ~231_

### marquee

- **`cube_awtrix_idle_effect_cycle`** — Cube AWTRIX - idle effect cycle — _line ~260_
- **`cube_awtrix_wakehint_cycle`** — Cube AWTRIX - wake-hint phrase cycle — _line ~278_

### persona

- **`1755313710558`** — Persona Switcher — _line ~299_
  <details><summary>context (persona_switcher.yaml)</summary>

  > (2) Head + body strips + Voice PE ring -> persona signature color. The script owns the
  > map (was inline here); it also gets called on HA start so a reboot re-asserts the look.
  > The Govee top light is no longer used — nothing here drives it. script.set_top_light_*
  > stays in scripts/lights/top_light.yaml in case we revive the top light later.

  </details>
- **`persona_switching_silence`** — Persona switching: silence during the show — _line ~328_
- **`persona_switching_stuck_watchdog`** — Persona switching: watchdog (unstick after 2 min) — _line ~366_

### voice

- **`cube_voice_mic_guard_and_marquee`** — Cube Voice - mic guard + marquee status — _line ~389_
  <details><summary>context (mic_guard_and_marquee.yaml)</summary>

  > (inline) 563: the mic reopens when the TTS stream finishes DOWNLOADING, not
  > Stuck-mute safety: satellite has been idle 10s (conversation truly over, not the
  > mid-response responding→idle→listening blip, which lasts <100ms).
  > (1) Cube starts speaking ('responding') -> mute mic so the early mic-reopen can't
  > hear the TTS; clear our status so the persona's marquee shows. The wake chime
  > at conversation start is NOT 'responding', so a fresh start never mutes.
  > (2) Real playback ended -> let the tail die, unmute, and if we're now listening
  > for the visitor, that's the true LISTENING moment. This is the ONLY normal
  > unmute path — do not add others without re-reading the header comment.
  > persona_switching guard: during a Rails-side grand entrance the silence
  > automation above owns the mute switch (its media_stop fires this trigger) —
  > hands off until the flag drops and that automation unmutes.
  > Brain thinking.
  > Genuine listening (NOT the premature during-playback reopen) -> LISTENING.
  > The premature reopen can beat the media player to 'playing' by ~140ms, so the
  > media check alone races; the mute switch is the reliable tell — we muted at
  > 'responding' and a genuine listening moment is never muted.
  > Idle 10s -> stuck-mute safety (e.g. TTS errored and media never played) + clear
  > marquee. Media-not-playing guard so a still-playing tail can't get the mic opened.
  > persona_switching guard: same hands-off as the tts_done path — the grand-entrance
  > show keeps the mic muted longer than 10s of satellite idle.

  </details>

## Scripts (`scripts.yaml`)

### audio

- **`persona_attention_announce`** (`script.persona_attention_announce`) — Persona Attention Announce — _line ~2_
- **`play_attention_sfx`** (`script.play_attention_sfx`) — Play Attention SFX — _line ~82_
  <details><summary>context (attention.yaml)</summary>

  > --- Idle attention (SFX + persona call-out) -------------------------------------
  > Fired by the "Idle: attention ping" automation when the cube's been idle a while, to
  > draw people over. Two scripts: a full persona voiced call-out (glitch blip + the persona's
  > own cloud voice via tts.cloud_say) and a bare sound-effect. Both play out the cube's OWN speaker
  > (media_player.cube_cube_voice_media_player), NOT the jukebox — there's no conversation in
  > flight (the automation requires 3 min idle), so it can't step on a pipeline.
  > SFX files live at /media/sounds/effects/glitch_*.mp3 on the box — glitchy radio-static
  > "beep-bloops" (sourced from data/rails_media/glitch_efx/short, all <10s). persona_attention_announce
  > plays a short one as a pre-chime then speaks; play_attention_sfx plays one straight through
  > media_source. Persona -> Nabu Casa cloud voice mirrors the voice_id in each lib/prompts/personas/*.yml.
  > Persona -> Nabu Casa cloud voice + locale. SOURCE OF TRUTH is the live Assist pipelines
  > on the box (select.cube_cube_voice_assistant → Buddy/Jax/Neon/Zorp/Crash pipeline's
  > tts_voice/tts_language), NOT the repo personas *.yml voice_id (those are stale). Keep
  > these in sync with the pipelines if the pipeline voices change.
  > Glitchy radio-static "beep-bloop" pre-chime. Shorter subset (<6s) so it doesn't drag
  > before the voice line. Files under /media/sounds/effects/ (from data/rails_media/glitch_efx).
  > Same random openers the old presence voice-nudge used (always ended with the wake hint).
  > Snapshot the body light so we can put it back exactly as it was after the sparkle.
  > Pre-chime: play a short glitch blip, let it ring a moment, then the persona speaks. Both
  > go out the cube's own voice speaker; the cloud_say interrupts the tail of the blip (a
  > deliberate glitchy cut-to-voice). tts.cloud_say (legacy Nabu Casa cloud) — chime_tts's TTS
  > backend produced no audio on this box, but cloud_say works. cache:true caches each phrase.
  > Hold the sparkle across the spoken line, then restore the body light to what it was.
  > Glitchy radio-static "beep-bloop" pool (all <10s), from data/rails_media/glitch_efx.

  </details>
- **`play_song_on_jukebox`** (`script.play_song_on_jukebox`) — Play Song on Jukebox — _line ~109_
- **`play_mood_music_on_jukebox`** (`script.play_mood_music_on_jukebox`) — Play Mood Music on Jukebox — _line ~166_
- **`search_jukebox`** (`script.search_jukebox`) — Search Jukebox — _line ~219_
  <details><summary>context (jukebox.yaml)</summary>

  > Two play scripts for the jukebox — one for front-and-center SONGS, one for background/MOOD
  > music. They're functionally the same (fuzzy-search a track and play it on
  > media_player.jukebox_internal) except for volume and timing, and neither takes a volume
  > field anymore: volume is HARDCODED per script and faded in, so the agent can't leave it in a
  > weird state. (The jukebox_internal media player is still exposed, so the agent CAN nudge
  > volume directly after the fact if it really wants to.)
  > play_song_on_jukebox       — vol 90, waits for the persona to stop speaking first, fades in.
  > play_mood_music_on_jukebox — vol 60, starts right away, fades in.
  > Fade: set volume to 0, start playback, then ramp to target over ~3s (6 steps × 0.5s).
  > Hold until the cube stops speaking so the song lands after the words, not over them.
  > Outside a conversation the VA media player isn't playing, so this passes through instantly.
  > Fade 0 -> 90 over ~3s.
  > Fade 0 -> 60 over ~3s.

  </details>
- **`systems_check`** (`script.systems_check`) — Systems Check — _line ~254_
  <details><summary>context (systems_check.yaml)</summary>

  > --- Systems check (cosmetic) ------------------------------------------------------
  > A fake diagnostic: the cube plays a glitch-static blip then speaks one of a few cheeky
  > canned lines in a flat, non-persona "system" voice out its OWN speaker. It does NOT check
  > anything. Exposed to the action agent so when a persona asks to "run a systems check" the
  > agent can call it — it just plays the bit. Rarely called; nobody needs to care that it's fake.
  > Voice is deliberately a non-persona cloud voice (JennyNeural) so it reads as "the machine,"
  > not the current persona — swap it if you want a more robotic one.
  > Glitch-static blip first, for the diagnostic-machine feel, then the readout.

  </details>

### connectivity

- **`enter_rest_mode`** (`script.enter_rest_mode`) — Enter Rest Mode (internet down) — _line ~291_
- **`wake_from_rest`** (`script.wake_from_rest`) — Wake From Rest (internet back) — _line ~333_
  <details><summary>context (rest_mode.yaml)</summary>

  > --- Internet "resting" mode -----------------------------------------------------
  > Put the cube to sleep when the internet is gone (script.enter_rest_mode) and wake
  > it back up when it returns (script.wake_from_rest). Driven by the connectivity
  > automations in automations.yaml; the sensor + internet_resting flag live in
  > packages/glitchcube_connectivity.yaml. See
  > docs/superpowers/specs/2026-07-14-internet-outage-resting-mode-design.md.
  > Go to sleep: hold a "come back later" sign, dim everything to low red, mute the
  > mic, stop the music, drop into low_power. Idempotent — the down automation
  > re-runs this every 5 min while the outage lasts, so it also re-asserts the sign
  > after e.g. a marquee power-cycle.
  > Mute the mic — nothing works offline, don't invite conversations. The wake
  > path leaves this to the grand entrance's persona_switching drop to un-mute.
  > No point playing to no one; saves battery too.
  > Dim red on the body WLED strip...
  > (The Govee top light is no longer used, so rest mode no longer sets it. The
  > script.set_top_light_* scripts remain in scripts/lights/top_light.yaml if revived.)
  > Marquee: dim the sign, then hold the resting message (hold:true = stays until
  > dismissed; the idle-cycle only touches the background app underneath).
  > Wake up: clear the sign, restore normal marquee brightness + a fresh idle screen,
  > back to conversation mode, then kick off the Rails grand entrance. The entrance
  > (Shows::GrandEntrance) owns the rest — anomaly VO, lights re-sync, theme song,
  > arrival announce — and its persona_switching drop un-mutes the mic, so we do NOT
  > un-mute here (mic stays shut through the show).
  > Fire-and-forget: Rails picks a fresh persona (not the cube-dominator, not the
  > previous session) and runs the whole arrival show.

  </details>

### lights

- **`set_cube_lights`** (`script.set_cube_lights`) — Set Cube Lights — _line ~359_
  <details><summary>context (cube_lights.yaml)</summary>

  > --- Cube WLED lighting (Assist-facing) ------------------------------------------
  > The ONE addressable-LED control exposed to the Assist action agent. The cube's show
  > LEDs are a single sound-reactive WLED strip on the cube's BODY (light.cube_body_wled).
  > (The controller's second output — the old head strip — is unused and unexposed; the
  > head cube is lit by the Voice PE's built-in LED ring, firmware-controlled.) The agent
  > just picks an optional color + brightness and an effect; routing lives here so the
  > agent only ever sees one lighting tool.
  > Hold the light change until the cube stops speaking so it lands with (not under) the
  > words. Key off the VOICE media player, not the satellite 'responding' state — the
  > firmware blips responding->idle->listening mid-speech, which would release too early.
  > Outside a conversation the media player isn't playing, so this passes through instantly.
  > Build the payload: always set the effect (Solid by default), and only include
  > color/brightness when the caller actually passed them so we don't clobber them.
  > queued so back-to-back calls run in order instead of dropping one.

  </details>
- **`sync_lights_to_persona`** (`script.sync_lights_to_persona`) — Sync Lights To Persona — _line ~587_
  <details><summary>context (sync_lights_to_persona.yaml)</summary>

  > --- Persona color sync ------------------------------------------------------
  > The ONE place the persona->RGB map lives now (previously duplicated in the
  > Persona Switcher automation's ring step). Applies the current persona's
  > signature color to the cube's expressive lights: the body WLED strip (solid)
  > and the Voice PE LED ring (rgb + full brightness; the ring has its own
  > firmware effect set — it runs its own listening/processing animations — so we
  > don't send it a WLED effect name). The Persona Switcher automation calls this
  > on every persona change.

  </details>
- **`set_top_light_persona_color`** (`script.set_top_light_persona_color`) — Set Top Light to Persona Color — _line ~612_
- **`set_top_light_effect`** (`script.set_top_light_effect`) — Set Top Light Effect — _line ~634_
  <details><summary>context (top_light.yaml)</summary>

  > --- Top light preset effects ----------------------------------------------------
  > INTERNAL ONLY — the top light is NOT exposed to Voice Assist; Assist controls the WLED
  > body/head segments instead. These scripts and the top-light automations are the only
  > things that drive it.
  > The top light (light.top_light, a govee2mqtt device that now sits on top of the cube)
  > is set directly for solid colors/brightness — e.g. script.set_top_light_persona_color
  > for the persona ambient glow. Its companion scene selects kept their original ids
  > (select.cube_light_scene / select.cube_light_diy_scene / select.cube_light_music_mode);
  > renaming the light entity does not rename them. Two convenience scripts pick named looks:
  > set_top_light_effect        -> static scenes: the full built-in catalog (~97) plus the
  > non-reactive DIY scenes. Built-in ones route through
  > select.cube_light_scene, DIY ones through
  > select.cube_light_diy_scene. (Rails shows call this for
  > the grand-entrance glitch beat; slated to move to the
  > automation layer later.)
  > (A sound-reactive top-light script + its jukebox automation used to live here; both were
  > retired. For music-reactive light now, use the WLED sound-reactive effects in
  > script.set_cube_lights.)
  > Set the top light to the current persona's signature color, solid, dimmed to a low
  > ambient level (brightness 15) — the top light's default ambient glow. Central home for the persona->RGB map (mirrors the
  > voice LED ring colors in the Persona Switcher automation); called by that automation and
  > by the blink-test restore.
  > Built-in scenes (select.cube_light_scene)
  > Non-reactive DIY scenes (select.cube_light_diy_scene). Add new DIY scenes
  > here as they're created on the device.
  > DIY scene.
  > Built-in scene.

  </details>

### marquee

- **`awtrix_marquee_message`** (`script.awtrix_marquee_message`) — AWTRIX Marquee Message — _line ~790_
- **`awtrix_marquee_restore_brightness`** (`script.awtrix_marquee_restore_brightness`) — AWTRIX Marquee Restore Brightness — _line ~877_
- **`awtrix_marquee_clear`** (`script.awtrix_marquee_clear`) — AWTRIX Marquee Clear — _line ~908_
- **`set_marquee_idle`** (`script.set_marquee_idle`) — Set Marquee Idle Effect — _line ~918_
- **`set_marquee_wakehint`** (`script.set_marquee_wakehint`) — Set Marquee Wake Hint — _line ~1029_
- **`awtrix_install_idle_apps`** (`script.awtrix_install_idle_apps`) — AWTRIX Seed Idle Apps — _line ~1073_
  <details><summary>context (marquee.yaml)</summary>

  > --- AWTRIX marquee (real) -------------------------------------------------------
  > Drives the physical AWTRIX LED sign (HASS device "awtrix_marquee") directly over
  > MQTT. The awtrix.* services are NOT registered on this box, so we publish to the
  > device's own MQTT topic. The topic PREFIX is "marquee" — reported by
  > sensor.cube_awtrix_marquee_device_topic — NOT the HASS entity name "awtrix_marquee".
  > A notification interrupts the app loop, shows the text, then returns to normal.
  > Capture the current (idle) brightness so the tail can restore it after the message.
  > The AWTRIX matrix light's brightness IS the device BRI setting (0-255); the idle
  > screen often runs dim, which would make an un-boosted message hard to read.
  > Force full brightness FIRST so the notification is always readable, even when the
  > idle screen was dimmed down.
  > NON-BLOCKING: fire-and-forget the brightness restore so this script returns instantly
  > (the calling conversation agent no longer waits out the whole message duration). The
  > tail sleeps for the message's life, then restores the captured idle brightness.
  > --- AWTRIX background apps (two always-on apps the device cycles) ----------------
  > The marquee runs TWO always-on custom apps that the device auto-cycles: "idle" (an
  > ambient effect) and "wakehint" (the "say Hey Glitchcube to wake me up" hint). App
  > transitions are ON (ATRANS=true) with a 20s cycle time (ATIME=20 — this firmware counts
  > ATIME in SECONDS, not ms; set in the seed below), so the two apps toggle every ~20 seconds. Transient notifications
  > (awtrix_marquee_message) overlay whichever app is showing and then dismiss back to the
  > loop. An effect/text published to marquee/custom/<app> with NO duration holds until the
  > next publish. Division of labor: AUTOMATIONS decide WHEN to change each app; the
  > set_marquee_idle / set_marquee_wakehint SCRIPTS decide WHAT each shows.
  > (Replaced the old presence-nudge marquee automation — the wake hint lives on the sign now.)
  > set_marquee_idle — the "what". Call with nothing for a random effect/palette/speed, or
  > pass any subset to dial in a specific look. Publishes retained, no duration.
  > set_marquee_wakehint — the "wakehint" app (the second always-on app the device cycles
  > with the idle effect). Call with no args for a random wake-hint phrase, or pass `message`
  > to pin one. Publishes retained to marquee/custom/wakehint with NO duration, so it holds as
  > an app in the loop until the next publish. The wakehint-cycle automation re-rolls the
  > phrase every minute so the hint varies; the device's ATIME governs how long it shows.
  > rainbow by default; an explicit `color` arg pins a solid color instead
  > Seed after a device reflash: enable app transitions with a 30s cycle time (both wiped by
  > reflash) so the two always-on apps toggle, then seed both apps. Run once; the idle-effect
  > and wakehint cycle automations take over from there.

  </details>

### persona

- **`set_persona_quick`** (`script.set_persona_quick`) — Set Persona (quick) — _line ~1096_
- **`hand_off_the_cube`** (`script.hand_off_the_cube`) — Hand Off The Cube (grand entrance) — _line ~1131_
  <details><summary>context (persona.yaml)</summary>

  > --- Persona switching -------------------------------------------------------
  > The quick, fanfare-free persona switch. It writes input_select.current_persona,
  > which the "Persona Switcher" automation watches to swap the Assist voice pipeline —
  > so the script needs not touch the pipeline itself. `persona` is optional; omit it to
  > pick a random one (excluding whoever is current).
  > The GRAND entrance (anomaly VO, theme song, marquee, arrival announcement) is NOT a
  > HASS script anymore — it's Rails-side (Shows::GrandEntrance), sequenced in Ruby with
  > audio played straight off the Rails host. Rails raises input_boolean.persona_switching
  > for the duration, as a hook for any HASS-side automations that want to react.
  > Light touch so a manual switch is visible on the sign. (Add an SFX here later if wanted.)
  > --- Hand off the cube (grand entrance) --------------------------------------
  > The theatrical persona switch: the current persona gives up its turn and hands the
  > cube to another, who arrives with a full grand entrance. Exposed to Assist so a
  > persona can trigger it in character. Fire-and-forget: it pokes Rails
  > (rest_command.glitchcube_grand_entrance) and returns; the show runs async.

  </details>

