# Operating the cube on prod (bigbuddy)

Prod is a Mac Mini (`bigbuddy`) running the whole stack under **launchd**. HASS lives
in a UTM VM named `glitch`. Everything starts automatically on power-up (auto-login +
RunAtLoad) and **auto-restarts on crash** (KeepAlive). You normally don't touch anything —
these scripts are for when you do.

> Running any of these over SSH? rbenv isn't initialized in ssh shells, so prepend:
> `export PATH="$HOME/.rbenv/shims:$PATH"` (project ruby is 3.3.x). Run from the repo root.

## `bin/glitchcube-ctl` — control the running stack

The boot supervisor (`com.glitchcube.boot`) runs `glitchcube-boot`, which starts the VM in
the background and then `foreman` (Puma on :4567 + SolidQueue). Control it with:

```bash
bin/glitchcube-ctl start     # start it now (VM ensure + Rails + jobs)
bin/glitchcube-ctl stop      # take it DOWN and keep it down (see note) — for maintenance
bin/glitchcube-ctl restart   # graceful restart (TERM; KeepAlive respawns it)
bin/glitchcube-ctl status    # launchd state of both agents + support services
bin/glitchcube-ctl logs      # tail log/boot.out.log + boot.err.log
bin/glitchcube-ctl unload    # remove the boot agent from launchd (re-add with install-boot)
```

**Why `stop` is special:** the agent is `KeepAlive=true`, so a plain kill just gets
resurrected. `stop` therefore *boots the job out of launchd* so it stays down while you work.
The plist stays on disk, so a **real reboot still starts it** (RunAtLoad). Bring it back with
`bin/glitchcube-ctl start`.

## `bin/install-boot` — first-time install / reinstall

Run once (from the logged-in GUI session, not a bare ssh) after cloning or when the launchd
plists change:

```bash
bin/install-boot
```

Installs two user LaunchAgents from `deploy/launchd/`:
- **`com.glitchcube.boot`** — starts VM + Rails at login/power-cycle, auto-restarts on crash.
- **`com.glitchcube.squeezelite`** — the audio player (KeepAlive). MAC is pinned with `-m`
  so Music Assistant always sees the same player (== `media_player.jukebox_internal`).

Requires: auto-login ON for `estiens`, ruby installed (`rbenv versions`), and the UTM VM
named `glitch`.

## The other scripts (called by the boot flow — you rarely run these directly)

- `bin/glitchcube-boot` — the supervisor entrypoint launchd runs. Ensures the VM, reaps any
  orphaned Puma/SolidQueue from a crashed instance, then `exec foreman`.
- `bin/ensure-hass-vm` — starts the UTM VM + attaches the SkyConnect/zigbee dongle, all in
  the background so **Rails never waits on HASS** to boot.
- `bin/check-services` — one-line status of Ollama (:11434) + Squeezelite (informational).

## "The cube didn't come up" — quick triage

```bash
bin/glitchcube-ctl status                    # are the agents running?
bin/glitchcube-ctl logs                       # what did boot say? (Ctrl-C to stop)
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:4567/up   # Rails? (expect 200)
curl -s -o /dev/null -w '%{http_code}\n' http://glitch.local:8123/  # HASS?  (expect 200)
```

- Rails up but HASS down → the VM is still booting (give it ~1–2 min) or check UTM.
- Nothing running → confirm auto-login is on; `bin/glitchcube-ctl start` to kick it.
- Note: logs (`log/boot.{out,err}.log`) aren't rotated — a persistent crash loop will grow
  them. If you see that, fix the cause (it's failing loudly) rather than ignoring it.
