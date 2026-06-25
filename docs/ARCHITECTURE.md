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
| Device actuation (lights, music, display, effects) | **HASS** | HASS entities/services | Rails *requests* changes via the translator; HASS performs them. |
| Raw sensor + world events | **HASS** → Rails | `POST /ha/world_state/trigger` | HASS pushes state changes; `WorldStateUpdaters::Registry` (allowlist) routes them. |
| Current persona | **HASS** (source of truth) | `input_select.current_persona` | `CubePersona.current_persona` reads HASS first; cached in Rails.cache (30 min). |
| Cube mode / battery / low-power | **HASS** | `input_select.cube_mode`, etc. | Read via `CubeData` sensor registry. |
| GPS / location | **HASS** → Rails | `sensor.glitchcube_*` | `Gps::GpsTrackingService` reads; `LocationContextService` resolves to BRC geography. |
| Conversation state + history | **Rails** | `ConversationLog`, `Conversation` (pgvector) | The brain's working memory of a session. |
| Long-term memory | **Rails** | `ConversationMemory`, `Fact` (pgvector) | Semantic recall + brain-flagged storage (see Memory loop). |
| Goals / policy / persona behavior | **Rails** | `GoalService`, persona YAML, prompt builders | The only place behavior logic is versioned. |
| Decisions (what to say, what to do) | **Rails** | `ConversationNewOrchestrator` | The brain. |
| Pending action/query results across turns | **Rails** | `conversation.metadata_json` | `pending_ha_results`, `pending_query_results` — surfaced next turn. |

## Conversation pipeline (two LLM roles)

`POST /api/v1/conversation` → `ConversationNewOrchestrator` runs six steps in a
transaction: **Setup → PromptBuilder → LlmIntention → ActionExecutor →
ResponseSynthesizer → Finalizer**.

Two distinct LLM roles, configured independently in
`config/initializers/config.rb` (all default to the same fast model today):

- **Brain** (`brain_model`, `DEFAULT_AI_MODEL`/`BRAIN_MODEL`): runs in
  `LlmIntention` with `NarrativeResponseSchema`. Returns `speech_text`, a single
  plain-English **`environment_instruction`** ("turn the lights orange and play
  heavy metal"), inner state, optional `search_memories`, and optional
  `memories` to remember. The brain never emits tool calls.
- **Translator** (`translator_model`, `TOOL_CALLING_MODEL`): `ToolCallingService`,
  run at low temperature. Converts the one `environment_instruction` into
  validated HASS tool calls (with a retry/validation loop).
- **Summarizer** (`summarizer_model`, `SUMMARIZER_MODEL`): background
  summarization.

**Speak-first, act-async:** speech is returned immediately; the
`environment_instruction` is dispatched to `EnvironmentDirectorJob`, which runs
the translator + execution in the background. Results land in
`pending_ha_results` and surface to the brain on the next turn. There is no
per-domain agent fan-out — one brain, one translator.

## Memory loop (recall → store)

A minimal, event-ready loop — not a multi-job summarization pipeline:

- **Proactive recall (read):** `Prompts::SystemContextEnhancer` injects recent
  high-importance memories (`Memory::MemoryRecallService`) into the system prompt
  each turn. Cheap — no per-turn embedding.
- **On-demand recall (read):** the brain may request specific
  `search_memories`; `ActionExecutor` runs them through `rag_search` and
  `ResponseSynthesizer` defers the results into `pending_query_results` so they
  surface on the next turn.
- **Store (write):** the brain flags facts worth keeping in the schema's
  `memories` field; `Finalizer` enqueues `MemoryStoreJob`, which persists them as
  `ConversationMemory` (async, so the embedding write never blocks speech).

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
