# GlitchCube Architecture

A durable map of how the system is wired and **who owns what state**. For the
revival effort's decisions and history, see [REFACTOR_NOTES.md](./REFACTOR_NOTES.md).

## The split: HASS is the body, Rails is the brain

Home Assistant (HASS) provides the cube's senses and actuators; Rails owns all
behavior and decisions. Keeping this boundary clean is the single most important
architectural rule here — when "which code lives where" gets confusing, this
table is the answer.

| Concern | Owner | Where it lives | Notes |
|---|---|---|---|
| Wake word, STT, TTS | **HASS** | Voice pipeline + custom component | HASS hears and speaks; Rails never touches audio. |
| Device actuation (lights, music, display, effects) | **HASS** | HASS entities/services | Rails emits a plain-English instruction; a dedicated HASS **action agent** decodes it to tool calls and performs them. |
| Raw sensor + world events | **HASS** → Rails | `POST /ha/world_state/trigger` | HASS pushes state changes; `WorldStateUpdaters::Registry` (allowlist) routes them. |
| Current persona | **HASS** (source of truth) | `input_select.current_persona` | `CubePersona.current_persona` reads HASS first; cached in Rails.cache (30 min). |
| Cube mode / battery / low-power | **HASS** | `input_select.cube_mode`, etc. | Read via `CubeData` sensor registry. |
| GPS / location | — | `Gps::*`, `Landmark`/`Street` | **Dormant reference code** — not wired into anything live; empty tables. |
| Conversation state + history | **Rails** | `ConversationLog`, `Conversation` | The brain's record of a session. |
| World state (continuity) | **Rails** (file) | `storage/world_state.md`, `WorldState` | **Dormant** — service lingers but is no longer injected into prompts (amnesiacube). |
| Long-term memory | **Rails** | `Memory`, `MemorySearchService` | **Dormant** — nothing writes or reads it in a turn (amnesiacube). |
| Policy / persona behavior | **Rails** | persona config + prompt builders | The only place behavior logic is versioned. No goal system. |
| Decisions (what to say, what to do) | **Rails** | `ConversationOrchestrator` | The brain. |
| Pending action results across turns | **Rails** | `conversation.metadata_json` | `pending_ha_results` — action agent's reply, surfaced next turn. |

## Conversation pipeline (brain in Rails, tool-calling in HASS)

**Full walkthrough with class names + the HASS-side two-agent design:
[`conversation_flow.md`](conversation_flow.md).** In brief:

`POST /api/v1/conversation` → `ConversationOrchestrator` runs six steps in a
transaction: **Setup → PromptBuilder → LlmIntention → ActionExecutor →
ResponseSynthesizer → Finalizer**.

Only **one** LLM role lives in Rails now — the brain. Tool-calling was moved out to
a HASS conversation agent:

- **Brain** (`brain_model`, `DEFAULT_AI_MODEL`/`BRAIN_MODEL`): runs in
  `LlmIntention` via `LlmService.call_with_structured_output` +
  `NarrativeResponseSchema`. Returns `speech`, `inner_monologue`,
  `continue_conversation`, and a list of plain-English **`actions`**
  (`{action_name, description}`). It never emits tool calls and carries no memory
  fields (the cube is currently amnesiac — see Continuity).
- **Action agent (HASS-side, not an in-Rails role):** `ActionExecutor` flattens
  `actions` into one instruction and `EnvironmentDirectorJob` hands it to the HASS
  agent `Rails.configuration.hass_action_agent` via
  `HomeAssistantService#conversation_process`. That agent owns all tool-calling
  (Assist API + exposed entities) and replies in natural language.

There are also **per-persona HASS voice agents** (visitor-facing, one TTS voice
each) that do wake word / STT / TTS. The visitor talks to those; the action agent
never talks to a visitor.

**Speak-first, act-async:** speech is returned immediately; the instruction is
dispatched to `EnvironmentDirectorJob` in the background. The action agent's reply
lands in `conversation.metadata_json["pending_ha_results"]` and is folded into the
brain's context on the next turn. No per-domain fan-out, no in-Rails translator.

## Continuity — currently removed ("amnesiacube")

The cube has **no working memory or continuity right now.** Reflection, per-turn
memory recall/flagging, deep memory search, the multi-layer summarizers, and the
goal system were all deleted. The brain schema has no memory fields and no
world-state blob is injected into prompts.

Still present but **dormant** (nothing writes or reads them in a turn): the
`Memory` model, `MemorySearchService` (standalone plain-Rails query), and
`WorldState`/`storage/world_state.md`. Re-introducing continuity is future work.

`continuity.md` documents the **old** removed design and is banner-flagged as
superseded — don't treat it as current.

## Testing the cube without hardware

`FakeHomeAssistant` (injected via the `HomeAssistantService.instance=` seam)
serves scriptable entities/sensors/world state. The **scenario harness**
(`spec/integration/conversation_scenario_spec.rb`) drives the real orchestrator
against the fake with a canned brain response and asserts on observable output —
what the cube *says and does*. This replaced the old `scripts/*harness*` model
benchmarks (removed; they targeted the deleted two-tier architecture).
`PerformanceModeService` takes an injectable clock (`FakeClock`) so timed loops
run in virtual time, never against the wall clock.

## Naming note: `ConversationLog`

The per-turn record is `ConversationLog` in code (with a separate `Conversation`
session row). Earlier docs referred to it as `Conversation`/`Message`. **Decision
(2026-06-23): keep `ConversationLog`** — a rename has a wide cosmetic blast radius
and no functional benefit. `ConversationLog` is the canonical name; treat doc
mentions of a "Message" model as historical.
