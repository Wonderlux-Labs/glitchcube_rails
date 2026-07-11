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
| Continuity / memory | **Rails** | `Summary` (three-tier summarizer), `Prompts::ContextBuilder` | **Live** — `interaction`/`persona`/`overall` summaries injected into every turn's `# CURRENT CONTEXT`. See [`memory.md`](memory.md). |
| Ambient world state | **HASS** → Rails | `sensor.glitchcube_world_state` | **Live** — composite HASS sensor injected each turn by `ContextBuilder`. (The old `WorldState`/`storage/world_state.md` service is dormant/superseded.) |
| Deep-recall long-term memory | **Rails** | `Memory`, `MemorySearchService` | **Dormant** — plain-Rails recall query not wired into a turn (the summarizer covers continuity today). |
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
  fields — continuity comes from the summaries injected into its prompt, not its
  output (see Continuity).
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

## Continuity — the three-tier summarizer

Continuity is a **layered summarizer** (this replaced the old reflection/`WorldState`
design). Three tiers write `Summary` rows and `Prompts::ContextBuilder` folds the latest of
each into every turn's `# CURRENT CONTEXT`, plus the live HASS world-state sensor:

- **`interaction`** (running memory, every 10 min), **`persona`** (per persona, on switch),
  **`overall`** (big-picture/director, hourly). Each carries an in-world narrative
  (`summary_text`) plus an OOC steering side-channel in `metadata` (`ooc_note` /
  `director_note` / `active_threads` / `real_world_facts`).

Full detail: [`memory.md`](memory.md). Reflection, per-turn recall/flagging, deep memory
search, and the goal system remain deleted; the brain schema has no memory fields (continuity
comes from the injected summaries, not the brain's output).

Still present but **dormant** (nothing writes or reads them in a turn): the `Memory` model +
`MemorySearchService` (plain-Rails deep-recall query) and the old `WorldState` /
`storage/world_state.md`. `continuity.md` documents the **old** removed reflection design and
is banner-flagged superseded — don't treat it as current.

## Testing the cube without hardware

`FakeHomeAssistant` (injected via the `HomeAssistantService.instance=` seam)
serves scriptable entities/sensors/world state. The **scenario harness**
(`spec/integration/conversation_scenario_spec.rb`) drives the real orchestrator
against the fake with a canned brain response and asserts on observable output —
what the cube *says and does*. This replaced the old `scripts/*harness*` model
benchmarks (removed; they targeted the deleted two-tier architecture).

## Naming note: `ConversationLog`

The per-turn record is `ConversationLog` in code (with a separate `Conversation`
session row). Earlier docs referred to it as `Conversation`/`Message`. **Decision
(2026-06-23): keep `ConversationLog`** — a rename has a wide cosmetic blast radius
and no functional benefit. `ConversationLog` is the canonical name; treat doc
mentions of a "Message" model as historical.
