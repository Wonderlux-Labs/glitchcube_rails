# Rails-Owned Camera Snapshots — design

**Date:** 2026-07-11
**Status:** approved design, ready for implementation plan
**Supersedes:** `2026-07-10-camera-awareness-design.md` (the HASS/LLMVision pipeline)

## Goal

Same feature as yesterday's camera-awareness design — a short description of what the
cube's camera sees, injected into the brain's prompt — but with the whole capture→
describe→store pipeline owned by Rails instead of HASS. The webcam is physically on the
Rails host, so the old chain (webcam → ffmpeg publisher → mediamtx RTSP → HASS generic
camera → LLMVision → input_text) was five moving parts to move one JPEG across a machine
boundary and back. New chain: one-shot ffmpeg capture → OpenRouter vision call →
`input_text.set_value`. No always-on encoding, no RTSP, no LLMVision integration, and
model choice/fallback lives next to every other LLM knob we have.

What deliberately does NOT change:
- `input_text.current_camera_state` stays the store — HASS keeps its statefulness,
  last-changed history, and dashboard visibility.
- The HASS "Camera: clear stale description" automation stays (it only watches the
  input_text; it neither knows nor cares who writes it).
- `Prompts::ContextBuilder` — zero changes. Camera block injection is untouched.
- Effective visitor-facing behavior: description refreshes around active conversations,
  throttled to ~2 min, immediate when empty, gone 3 min after conversations stop.

Dropped (not just moved): the `input_button.refresh_camera_description` "cube asks for a
look" surface. It was wired but never exposed as a persona action, and a snapshot
requested mid-turn wouldn't land until the next round anyway — the turn-start refresh
already covers that. If we ever want a HASS-side trigger again: webhook → enqueue the job.

## Shape (one line)

Every conversation turn fire-and-forgets a job that (if the current description is empty
or stale) grabs one frame with ffmpeg, asks a vision model what it sees, and writes the
answer into `input_text.current_camera_state`.

## New Rails pieces

### `CameraDescriptionJob` (the whole pipeline, one file)

All logic lives in the job so the entire pipeline is visible in one place. Small methods:
`throttled? → capture! → describe → write`.

Constants (visible at the top of the job, per explicit preference — no adjustable
resolution/format knobs):

```ruby
SNAPSHOT_PATH    = Rails.root.join("tmp/camera/snapshot.jpg")  # dir created on demand
SNAPSHOT_COMMAND = %(ffmpeg -f avfoundation -video_size 1280x720 -pixel_format uyvy422 -i "0" -frames:v 1 -y #{SNAPSHOT_PATH})
THROTTLE_SECONDS = 120
CAPTURE_TIMEOUT  = 10 # seconds; kill a hung ffmpeg, fail loudly
CAMERA_STATE_ENTITY = "input_text.current_camera_state"        # same id ContextBuilder reads
```

Behavior:

1. **Throttle** — `perform(throttle_seconds: nil)`; param defaults to `THROTTLE_SECONDS`.
   Fetch the entity from HASS; skip (log + return) unless its state is blank or
   `last_updated` is older than the throttle. This replicates the old automation's
   debounce exactly (empty always refreshes; otherwise at most ~once per 2 min), and
   keeping it in the job means callers stay dumb.
2. **Capture** — shell out to `SNAPSHOT_COMMAND` with `CAPTURE_TIMEOUT`. Non-zero exit or
   missing/empty file raises — no fallback frames, no retries (art-project rules: fail
   loudly, we'll see it).
3. **Describe** — `LlmService.call_with_vision(prompt:, image_path:)` (below). Prompt is
   the same people-focused text the LLMVision script used (how many people, fashion/vibe,
   anything notable; 1–2 sentences), truncated to 255 chars (input_text max).
4. **Write** — `HomeAssistantService.call_service("input_text", "set_value",
   entity_id: CAMERA_STATE_ENTITY, value: description)`.

### `LlmService.call_with_vision(prompt:, image_path:, model: nil)`

Mirrors `generate_text`, plus an image: builds one user message whose content is the
OpenAI-style multimodal array — `[{type: "text", ...}, {type: "image_url", image_url:
{url: "data:image/jpeg;base64,..."}}]` — which `open_router_enhanced` passes through
untouched. Returns the text content.

Fallback (mirrors the existing `retry_structured_on_secondary` idiom): if the primary
call raises or returns blank, retry once on `Rails.configuration.vision_fallback_model`.
If that also fails, raise — the job fails, the old description ages out via the HASS
clear automation, nothing lingers.

### Config knobs (`config/initializers/config.rb`, matching the existing pattern)

```ruby
# Camera snapshot description (CameraDescriptionJob). Vision-capable models only.
config.camera_vision_model  = ENV["CAMERA_VISION_MODEL"]  || "google/gemini-3.5-flash"
config.vision_fallback_model = ENV["VISION_FALLBACK_MODEL"] || "qwen/qwen3.7-max"
```

(Defaults are suggestions — both swap live like the other model knobs.)

### Trigger

`ConversationOrchestrator` setup step enqueues `CameraDescriptionJob.perform_later`
fire-and-forget every turn. The job's throttle makes the common case a no-op HASS read.
Timing matches the old system in practice: the description lands mid-turn and is in the
prompt by the next round.

## Removals

Repo (`data/homeassistant/`):
- `automations.yaml`: delete `camera_refresh_description`. **Keep**
  `camera_clear_stale_description` unchanged.
- `scripts.yaml`: delete `refresh_camera_description`.
- `packages/glitchcube_core.yaml`: delete `input_button.refresh_camera_description` and
  its comment block; keep `input_text.current_camera_state` (update its comment to say
  Rails writes it now).

HASS box (manual, alongside the next config sync):
- Remove the LLMVision integration + provider and the generic camera entity
  (`camera.192_168_68_75`) — both UI-configured, so not in the repo YAML.

Rails host (user-handled, out of scope for the implementation plan):
- mediamtx and any webcam→RTSP publisher launchagent. Owner will deal with these on the
  prod box; they cost nothing while unused.

## Risk: macOS TCC camera permission

ffmpeg spawned from launchd-started Rails needs camera access in that process context.
Owner tests on the prod box (2026-07-12) and will be present to approve the TCC prompt if
one appears. Smoke test = `bin/rails runner "CameraDescriptionJob.perform_now"` under the
`com.glitchcube.boot` context. Escape hatch if the direct shell-out fights TCC: wrap the
capture in a small bash script and grant that. Not a blocker for writing the code.

## Testing

- **Job spec** — stub the capture (write a fixture JPEG to `SNAPSHOT_PATH` instead of
  running ffmpeg), stub `LlmService.call_with_vision`, drive against `FakeHomeAssistant`:
  assert the `input_text.set_value` service call, the 255-char truncation, and the
  throttle (fresh non-empty state → no capture, no LLM call, no write).
- **LlmService spec** — VCR cassette for `call_with_vision` (tiny fixture image), plus
  fallback-model behavior with the primary stubbed to fail.
- **ContextBuilder / scenario harness** — untouched; existing specs already cover the
  injection side.
- **Manual smoke** — the `perform_now` runner line above, on the prod box.
