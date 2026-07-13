This directory holds the ESPHome device configs built with the local `esphome` CLI
(secrets in `secrets.yaml`, gitignored):

- **`cube-voice.yaml`** — Home Assistant Voice PE satellite (below).
- **`cube-screen.yaml`** — M5Stack Core2 status screen ([jump](#m5stack-core2--cube-screen)).

# Voice PE (Cube Voice) — ESPHome takeover

Custom firmware config for the Home Assistant Voice PE satellite
(`home-assistant-voice-09739d`, MAC `20:f8:3b:09:73:9d`). Stock 26.6.0 firmware as
a pinned package + a patched `voice_assistant` component fixing the self-STT
feedback loop (esphome/home-assistant-voice-pe#563). See the header comment in
`cube-voice.yaml` for the full story, and `grep -r "GLITCHCUBE PATCH" components/`
for the exact diff vs stock.

## Build & flash (OTA, no USB needed)

Use the ESPHome CLI at the same version the component was vendored from:

```bash
uvx esphome@2026.6.0 config  data/esphome/cube-voice.yaml   # validate
uvx esphome@2026.6.0 compile data/esphome/cube-voice.yaml   # first compile ~10-20 min (toolchain)
uvx esphome@2026.6.0 upload  data/esphome/cube-voice.yaml --device home-assistant-voice-09739d.local
```

(or `run` to compile+upload in one step; `logs` to tail the device log over the network.)

WiFi credentials and the HA API encryption key live in the device's NVS flash and
survive OTA reflashes — the config intentionally doesn't set them, so HA should
reconnect on its own after the reboot. If HA shows the device unavailable for more
than ~2 minutes after flashing, reload the ESPHome integration entry for it.

## Rollback

Flash the stock release back:

```bash
curl -LO https://github.com/esphome/home-assistant-voice-pe/releases/download/26.6.0/home-assistant-voice.factory.bin
```

then serve it to the device via the ESPHome web flasher (USB-C) — or simply point a
config at the unmodified package (delete the `external_components:` block) and OTA.

## Upgrading the pinned release later

1. Bump `@26.6.0` in `cube-voice.yaml`'s `packages:` line.
2. Re-vendor `components/voice_assistant/` from the matching `esphome/esphome` tag
   and re-apply the `GLITCHCUBE PATCH` hunks (or drop the vendored component
   entirely if upstream PR #16512 / issue #563 got fixed — check first).

## Smoke test after any flash

1. Wake word → short question → answer plays, follow-up window works.
2. Long persona speech (30s+) in continue mode: satellite must NOT transition to
   `listening` until playback ends (watch HA states for
   `assist_satellite.cube_cube_voice_assist_satellite` vs
   `media_player.cube_cube_voice_media_player`), no self-transcription loop.
3. Wake chime → immediate speech on a fresh start still works.
4. Device log line `Announcement still starting; deferring response finished`
   appearing during long TTS = the patch is doing its job.

---

# M5Stack Core2 — Cube Screen

`cube-screen.yaml` — a small always-on status screen. Exposes the Core2's on-board
sensors (battery %, MPU6886 IMU accel/gyro/temp, WiFi, uptime) to Home Assistant and
mirrors whatever text HA writes to **`input_text.m5_screen_text`** onto the LCD.

Node `cube-screen`, MAC `08:3a:f2:44:ef:38` (was the generic `esphome-web-44ef38`).

### The one gotcha: the AXP192

The Core2's LCD, backlight and touch are powered through an **AXP192 PMU** on the
internal I2C bus — nothing lights up until that chip is initialised, and ESPHome has
no built-in driver. So the config pulls one external component,
`github://martydingo/esphome-axp192` (`model: M5CORE2` does the whole power-rail +
backlight setup). Everything else (ILI9342C display, MPU6886 IMU) is native ESPHome.
Pins in the yaml are the fixed Core2 wiring.

### Build & flash (OTA)

```bash
esphome config   data/esphome/cube-screen.yaml                        # validate
esphome compile  data/esphome/cube-screen.yaml                        # first build ~10-20 min (toolchain)
esphome upload   data/esphome/cube-screen.yaml --device 192.168.68.66 # OTA (or cube-screen.local after first flash)
```

Notes:
- **WiFi creds are compiled into the firmware** (ESPHome doesn't carry them across a
  firmware replacement), so `secrets.yaml` must have `wifi_ssid` / `wifi_password`.
- **First OTA is passwordless** — matches the dashboard firmware that shipped on the
  device. The config sets a *new* `api_encryption_key`, so after the first flash the
  device drops out of HA and reappears for adoption: **Settings → Devices → add the
  discovered "Cube Screen", paste the key from `secrets.yaml`**. (The old
  `esphome-web-44ef38` entry can be deleted.)
- If the screen's colours look inverted, flip `invert_colors:` in the `display:` block.

### Writing to the screen from HA

Four HA helpers drive the screen (all created via the HA API):

- **`input_text.m5_screen_text`** — the text / caption line.
- **`input_text.m5_screen_emoji`** — a single emoji for the cube's mood. When set, the
  screen switches to "mood mode": the emoji drawn big and centred, with the text below
  it as a caption. Clear it (empty string) to go back to plain text mode.
- **`input_text.m5_screen_color`** — background colour by name
  (`red` `green` `blue` `yellow` `orange` `purple` `cyan` `pink` `white`) or `#RRGGBB`.
  Empty/unknown = black. Foreground text/emoji auto-switches black or white for contrast.
  Set a colour with empty text+emoji (or blank, below) to use the screen as a colour badge.
- **`input_boolean.m5_screen_blank`** — instant clear: shows only the background colour and
  hides text + emoji, *without* wiping their stored values, so flipping it back restores them.

```yaml
# mood mode — big emoji + caption
action: input_text.set_value
target: { entity_id: input_text.m5_screen_emoji }
data: { value: "🔥" }
# then optionally a caption
action: input_text.set_value
target: { entity_id: input_text.m5_screen_text }
data: { value: "feeling spicy" }
```

Emoji use the monochrome **Noto Emoji** font (colour emoji fonts don't render in
ESPHome's single-colour glyph engine). Only the codepoints listed in the `font_emoji`
`glyphs:` block are baked into flash — sending an emoji that isn't listed draws blank
and logs `Codepoint … not found`; add it to the list and reflash. **Flash is ~85% full**
with the current ~60-emoji set at 130px/4bpp, so trim the list (or drop `bpp`/`size`) if
you need room for a lot more.

In plain text mode (no emoji) the display word-wraps the text under a "GlitchCube" header.
