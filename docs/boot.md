# Boot & auto-start (bigbuddy)

How `bigbuddy` (the production Mac Studio) brings everything up after a power cut, and how the Rails
app is kept alive if it crashes. Goal: **flip the power on → everything comes up, no human needed.**

## What starts what

```
Mac boots
  └─ auto-login (estiens)                      ← required; enables the GUI session below
       ├─ brew services LaunchAgents           ← already installed, not managed here:
       │    postgresql@16, mosquitto (MQTT), redis, memcached, ollama, mediamtx, colima
       └─ com.glitchcube.boot  (LaunchAgent, RunAtLoad — no babysitter)
            └─ bin/glitchcube-boot
                 ├─ bin/ensure-hass-vm         ← starts the "glitch" UTM VM (Home Assistant)
                 └─ foreman start -f Procfile.dev
                      ├─ web:  Puma on :4567    (Rails, development env)
                      └─ jobs: bin/jobs         (SolidQueue)
```

Postgres, MQTT, Redis, etc. are **already** auto-started by their own Homebrew `brew services`
LaunchAgents — the boot supervisor does not touch them. It only starts the HASS VM and the Rails app.

This is a **boot/power-cycle starter, not a babysitter** (`KeepAlive=false`). It launches everything
at login; if something crashes it stays down — you go check on it (or power-cycle, since it runs off
batteries in the field). Crucially, any stop *you* do during development is respected — nothing
resurrects your `pkill`/`bin/glitchcube-ctl stop`.

To turn auto-restart-on-crash back on for a field deployment (e.g. Michigan), flip `KeepAlive` to
`<true/>` in `deploy/launchd/com.glitchcube.boot.plist` and re-run `bin/install-boot`. Note the
trade-off then: a plain `pkill` gets resurrected too, so to stop it during dev you'd use
`bin/glitchcube-ctl stop` (which unloads via launchctl and stays down).

## One-time setup

Run these once on bigbuddy, **from a logged-in session** (Screen Sharing / physical / VNC — utmctl
does not work over plain SSH):

1. **Enable auto-login** for `estiens`: System Settings → Users & Groups → *Automatically log in as*
   → `estiens`. Without this, nothing starts after a cold boot until someone logs in.
2. **Confirm Ruby** `3.3.9` is installed: `rbenv versions` (install with `rbenv install 3.3.9` if not).
3. **Confirm the VM name**: `/Applications/UTM.app/Contents/MacOS/utmctl list` → expect `glitch`.
   If it differs, edit `VM_NAME` in `bin/ensure-hass-vm`.
4. **Install the LaunchAgent**: `bin/install-boot`.

Deploy updates to the scripts with a normal `git pull` on bigbuddy; re-run `bin/install-boot` only if
the plist itself changed.

### Automation (TCC) permission for the VM — one-time, watch the screen

`utmctl` controlling UTM triggers a macOS **Automation** permission prompt ("… wants to control
UTM.app"). This is keyed to the *calling* process, so granting it to Terminal does **not** cover the
LaunchAgent — the first time the installed agent runs `utmctl start`, macOS prompts again, and a
prompt nobody clicks (headless boot) is denied by default.

So the first time you run `launchctl kickstart -k gui/$(id -u)/com.glitchcube.boot` (or the first
reboot after install), **be at the screen** (physically or via Screen Sharing) and approve the prompt
once. It persists across reboots afterward. If it ever gets denied, the VM just won't auto-start —
Rails still comes up (VM start is best-effort) — and you can re-trigger the prompt with another
kickstart, or grant it under System Settings → Privacy & Security → Automation.

## Operating it

Day to day, use the wrapper:

```bash
bin/glitchcube-ctl start      # run it now (VM + Rails + jobs)
bin/glitchcube-ctl stop       # stop it — stays stopped until you start / power-cycle
bin/glitchcube-ctl restart    # stop + start
bin/glitchcube-ctl status     # launchd state + last exit code
bin/glitchcube-ctl logs       # tail the supervisor logs
curl -sf http://localhost:4567/health   # is Rails up?
```

Under the hood these are `launchctl kickstart` / `kill TERM` / `print` against
`gui/$(id -u)/com.glitchcube.boot`. To fully uninstall the agent:
`launchctl bootout gui/$(id -u)/com.glitchcube.boot`.

## Adding more services later (camera/ffmpeg, etc.)

Two clean options, no changes to the supervisor:

- **Part of the app lifecycle** (starts/stops with Rails): add a line to `Procfile.dev`, e.g.
  `camera: ffmpeg -i rtsp://... ...`. foreman runs it alongside web/jobs.
- **Independent long-running daemon**: prefer a Homebrew `brew services` LaunchAgent (this is how
  `mediamtx`, the RTSP server, already runs) so it has its own lifecycle and logs.
