# Lakes of Fire networking — as-built (2026-07-16)

How the cube's network actually works at the burn, after a full evening of
debugging. **Read the address map before touching anything.**

## Topology

```
                    Starlink Mini  (ONE Wi-Fi SSID: "safehouse", 192.168.1.0/24, gw .1)
                          │
   ┌──────────────────────┼───────────────────────────────┐
   │                      │                               │
 bigbuddy (Mac)      voice satellite                 AWTRIX marquee / WLED /
 192.168.1.103       192.168.1.197                   other ESP devices
 (pinned: DHCP        (ESPHome)                      (192.168.1.x via DHCP)
  w/ manual addr)
   │
   ├── Rails (bin/dev, :4567)
   ├── squeezelite (jukebox audio out the headphone jack)
   ├── socat relays  *:8123 → VM, *:1883 → VM   ← how LAN devices reach HASS
   └── UTM "glitch" VM — **Shared Network (NAT)**, vmnet 192.168.64.0/24
         └── HASS OS  192.168.64.4  (gw/host = 192.168.64.1)
               ├── Music Assistant (:8095)
               ├── Mosquitto (:1883)
               └── tailscaled (100.79.82.74)
```

## The address map — who talks to whom

| Path | Address | Why |
|---|---|---|
| Rails → HASS | `http://192.168.64.4:8123` (`.env HOME_ASSISTANT_URL`) | direct vmnet hop, ~0.3ms, works with Starlink dead |
| HASS → Rails | `192.168.64.1:4567` via `input_text.glitchcube_host` (`SERVER_HOST=192.168.64.1` in `.env`) | vmnet gateway = the Mac, always reachable from the VM |
| squeezelite → MA | `-s 192.168.64.4` (launchd plist) | slimproto broadcast discovery can't cross NAT |
| LAN devices → HASS | `http://192.168.1.103:8123` (socat relay) | NAT'd VM is invisible to the LAN; the Mac relays |
| AWTRIX → MQTT | `192.168.1.103:1883` (set in the sign's web UI) | same relay pattern |
| HASS internal URL | `http://192.168.1.103:8123` | satellites fetch TTS audio from this URL |
| Humans, anywhere | tailscale `http://100.79.82.74:8123`, or Nabu Casa | admin door |

**Layering rule: machine-internal = vmnet (`192.168.64.x`); LAN devices =
`192.168.1.103` relays; humans = tailscale/Nabu Casa.** Each layer survives the
failure of the layers above it. The cube keeps talking with zero internet.

## Hard-won lessons (do not relearn these)

1. **Never bridge the VM to Wi-Fi.** 802.11 APs deliver unicast only to the
   associated station's MAC; macOS papers over it with a kernel MAC-NAT that
   intermittently drops IPv4 while IPv6/SLAAC keeps working — the VM "half
   vanishes" and every LAN device loses HASS. Shared Network (NAT) ended it.
2. **One SSID only.** The Mini had two networks (safehouse + justacube) on
   different subnets; bigbuddy auto-roamed between them after power cycles and
   the fleet split across subnets — hours of "the subnet changed!" confusion.
   justacube is deleted from the Starlink AND forgotten on bigbuddy.
3. **Do not use tailscale for host↔VM traffic.** Measured: it hairpins through
   the Starlink **public** IP (~61ms, `tailscale ping` showed `via 153.66.x.x`).
   MA marked the jukebox player unavailable on that path. Also dies with the dish.
4. **pf `rdr` does not work for this forward** (the Mac is not the LAN clients'
   gateway → reply-path asymmetry; and rdr intercepts en1 before any userland
   listener). Plain socat LaunchAgents, no root, KeepAlive. Don't re-try pf.
5. **squeezelite pins its output device** (`-o "External Headphones"`). It grabs
   a CoreAudio device at stream-open and ignores later default-output changes.
   Unplugging the jack makes it crash-loop until re-plug (KeepAlive self-heals).
6. **`input_text.glitchcube_host` can go stale across HASS reboots** (state
   restore) and Rails' boot-time registration silently fails if HASS isn't up
   yet. The recurring HostRegistrationJob (every 5 min, honors `SERVER_HOST`)
   self-heals it. Symptom of staleness: voice pipeline "stuck on thinking"
   (HASS POSTs conversation turns to a dead address).
7. **ESPHome/WLED mDNS re-discovery is dead under NAT** — if a device's DHCP
   address changes, HASS keeps dialing the old one forever. Fix per device (no
   restart needed): drive the config flow via REST —
   `POST /api/config/config_entries/flow` with
   `{"handler":"esphome","context":{"source":"reconfigure","entry_id":"<id>"}}`
   then `POST /api/config/config_entries/flow/<flow_id>` with
   `{"host":"<new_ip>","port":6053}` (WLED: handler `wled`, just `{"host":…}`).
   It aborts "already_configured" — that abort *applies the host update*.
   Entry ids: `GET /api/config/config_entries/entry`.
8. The prod HAOS ssh addon (`root@100.79.82.74`, pw in 1P/memory) rejects
   non-PTY exec — script it with `expect`, or better, use HASS REST/WS APIs.
9. Rails on bigbuddy runs **`bin/dev` (development)** — logs are in
   `log/development.log`, and foreman leaks `PORT=5100` into job env (cosmetic
   in registration log lines; the pushed value is the bare IP and the HASS
   component appends its `DEFAULT_PORT` 4567).

## After moving the rig / power loss — what happens by itself

Everything is persistent config: launchd agents (`com.glitchcube.boot`,
`com.glitchcube.squeezelite`, `com.glitchcube.fwd8123/1883` — all in
`deploy/launchd/`, installed by `bin/install-boot`), `.env`, the UTM config,
bigbuddy's pinned Wi-Fi address, HASS's internal URL, AWTRIX's broker.
Verified by clean-reboot test: core stack back in ~2m20s unattended;
`glitchcube_host` self-heals within 5 min.

**The one thing that can drift: LAN device IPs** (satellite/WLED/AWTRIX get
DHCP; leases are sticky by MAC but not guaranteed). If the satellite or WLED
don't reconnect within ~5 min of coming up, find the new IP
(`ping home-assistant-voice-09739d.local` / `ping glitch-wled.local` from any
Mac on safehouse) and run the reconfigure-flow fix from lesson 7. AWTRIX's
broker points at the Mac (pinned), so it never needs re-touching.

## Current device inventory (2026-07-16, leases may drift)

| Device | Address | Notes |
|---|---|---|
| bigbuddy | 192.168.1.103 | pinned (DHCP with manual address) |
| glitch VM | 192.168.64.4 | vmnet lease, sticky by VM MAC `d2:cb:80:04:ce:fb` |
| voice satellite | 192.168.1.197 | `home-assistant-voice-09739d.local` |
| WLED | 192.168.1.207 | `glitch-wled.local` |
| AWTRIX | 192.168.1.119 | web UI on :80, broker → 192.168.1.103 |

## Open items

- **Spotify in Music Assistant needs re-auth** — do the browser flow via the
  tailscale URL (`http://100.79.82.74:8095`).
- Boot-time host registration initializer should retry until HASS is up and
  push `host:port` explicitly (tonight it's covered by the 5-min job).
- The old `media_player.jukebox_internal_stale` MA player config and any other
  ghost squeezelite players can be deleted in MA Settings → Players.
- Post-burn (hardware): Starlink Mini USB-C→Ethernet adapter + the Deco as
  AP/router → wire bigbuddy's en0 → could return the VM to (wired) bridged and
  drop the relays. NAT works fine; only do this if there's a reason.
