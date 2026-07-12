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
