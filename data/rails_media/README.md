# Rails-host-only media

Audio that Rails plays straight off this machine's speaker (the Rails host IS the
cube's jukebox) via `HostAudio` — shelled-out `ffplay`, no HASS media_player hop.

- `theme_songs/` — the glitchcube theme song collection (mp3s, untracked). A random
  one plays during a grand-entrance persona switch (`Shows::GrandEntrance`), capped
  at 90s with a fade-out. Drop new songs in; nothing else to wire up.

Nothing in this directory is deployed anywhere. It is deliberately OUTSIDE
`data/homeassistant/` — that tree mirrors the HASS box's `/config` + `/media` and
gets scped over; these files must never take up the VM's disk. The media files are
gitignored (only this README is committed), so a fresh clone has an empty dir until
you copy the songs onto the host.
