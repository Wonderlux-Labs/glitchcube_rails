# Conversation & action flow (current)

High-level map of what happens when someone talks to the cube, and the class names
we actually use today. If you read one doc before touching the conversation path,
read this one. For the state-ownership table see [ARCHITECTURE.md](./ARCHITECTURE.md).

## Who does what

HASS owns the **visitor-facing voice**, Rails owns the **tool-calling**:

1. **Persona voice agents (HASS, visitor-facing).** One HASS conversation agent /
   pipeline **per persona**, each wired to that persona's **TTS voice**. The visitor
   only ever talks to the *active* persona's agent. This agent does the wake word,
   STT (speech→text), and TTS (text→speech) — it hears the visitor and later speaks
   the reply *in that persona's voice*. It does **not** decide what to say; it hands
   the recognized text to Rails.

2. **The in-Rails translator (`ToolCallingService`, never visitor-facing).** The brain
   emits plain-English action **channels** ("lights: turn the lights orange",
   "sound: play heavy metal"). A separate tool-calling LLM
   (`Rails.configuration.hass_tool_calling_model`) decodes each into concrete, validated
   Home Assistant tool calls (`Tools::Registry` → `Tools::BaseTool` subclasses), which
   execute by hitting the HASS **REST API** directly (`HomeAssistantService#call_service`,
   almost always `script.turn_on` + `variables:`). It runs in Rails so we get full
   visibility into what fired, easy parallelism, and dev/test with no live HASS
   (`FakeHomeAssistant`). Two lanes — `:action` and `:sound` — dispatched in parallel.

## End-to-end path

```
Visitor speaks
   │  (wake word + STT, HASS-side, active persona's pipeline)
   ▼
POST /api/v1/conversation            Api::V1::ConversationController#handle
   │  recognized text + session/context
   ▼
ConversationOrchestrator#call  ── 6 steps in a transaction ──────────────┐
   1. Setup               load/create Conversation, resolve persona       │
                          (HASS input_select.current_persona)             │
   2. PromptBuilder       system prompt (Prompts::SystemPromptBuilder) +  │
                          history + folds in LAST turn's action results   │
   3. LlmIntention        BRAIN LLM call (LlmService                      │
                          .call_with_structured_output +                  │
                          Schemas::NarrativeResponseSchema)               │
                          → { speech, inner_monologue, actions[],         │
                              continue_conversation }                     │
   4. ActionExecutor      split action channels into 2 lanes             │
                          (:action / :sound); EnvironmentDirectorJob      │
                          .perform_later per lane (speak-first, async)    │
   5. ResponseSynthesizer package speech + persona TTS voice              │
                          (CubePersona#tts_voice)                         │
   6. Finalizer           persist ConversationLog, tokens/cost,           │
                          HASS-formatted JSON                             │
   ▼ (returns immediately — does NOT wait on the translator) ────────────┘
HASS speaks the reply in the active persona's voice
```

Meanwhile, dispatched in the background (one job per lane, in parallel):

```
EnvironmentDirectorJob#perform  (lane derived from convo_prefix)
   │  ToolCallingService#execute_intent(instruction, lane:, persona:, …)
   ▼
TRANSLATOR LLM (in Rails)  → validated tool calls (retry on validation error)
   │                        → Tools::Registry.execute_tool
   │                        → HomeAssistantService#call_service (HASS REST)
   ▼
normalized result { success, narrative, tool_calls, service_calls, error }
   │
   ▼
store on conversation.metadata_json["pending_ha_results"]  (narrative + what fired)
   │
   ▼
NEXT turn, step 2: PromptBuilder#inject_previous_ha_results folds the narrative
(or error) back into the brain's context, so the cube knows what actually
happened and can own its own failures instead of hallucinating success.
```

## Why speak-first / act-async

Speech is returned to HASS **immediately**; the translator + tool execution run in the
background job while the persona voice is being read aloud. Device changes therefore land
a beat after the words, and their result is available by the next turn — never blocking
speech on tool completion. The two lanes (`:action` and `:sound`) run as separate jobs
concurrently.

## Class / responsibility quick reference

| Piece | Class / location | Role |
|---|---|---|
| HTTP entry | `Api::V1::ConversationController#handle` | Parse HASS payload, call orchestrator, format reply for HASS |
| Orchestrator | `ConversationOrchestrator` | The 6-step turn pipeline |
| Prompt assembly | `ConversationOrchestrator::PromptBuilder`, `Prompts::SystemPromptBuilder` | System prompt + history; folds in last turn's action results |
| Brain LLM call | `ConversationOrchestrator::LlmIntention` + `LlmService.call_with_structured_output` | One structured narrative call |
| Brain output shape | `Schemas::NarrativeResponseSchema` | `speech`, `inner_monologue`, action channels, `continue_conversation` |
| Action dispatch | `ConversationOrchestrator::ActionExecutor` | Split channels into `:action` / `:sound` lanes, enqueue one job each |
| Translate + execute | `EnvironmentDirectorJob` → `ToolCallingService` → `Tools::Registry` → `HomeAssistantService#call_service` | In-Rails translator LLM → validated HASS tool calls |
| Result carry-over | `conversation.metadata_json["pending_ha_results"]` ← job; → `PromptBuilder#inject_previous_ha_results` | Action outcome surfaces next turn |
| Speech + voice out | `ConversationOrchestrator::ResponseSynthesizer`, `CubePersona#tts_voice` | Speech text + persona TTS voice/language |
| Persona resolution | `CubePersona.current_persona` (HASS `input_select.current_persona`, cached 30 min) | Which persona is active |

## What is NOT in this flow anymore

The brief **HASS-conversation-agent** design — where `EnvironmentDirectorJob` POSTed each
channel to a HASS Assist agent (`conversation_process`) that owned the tool-calling — is
gone. Tool-calling is back in Rails (`ToolCallingService` + `Tools::Registry`, rebuilt for
current hardware) for visibility, parallelism, and no-live-HASS dev/test. The heavier bits
of the *original* in-Rails stack (`ToolExecutor`, `AsyncToolJob`, sync/async tool_type, the
stale device tools) stay retired under `deprecated/tool_calling/` (see its README) — the
job is now the async boundary, so those aren't needed.

## Memory & continuity

Continuity is a **three-tier summarizer** — see [`memory.md`](./memory.md) for the full
picture. In brief: `interaction` (running, every 10 min), `persona` (per persona, on
switch), and `overall` (big-picture/director, hourly) `Summary` rows are written by
`SummarizerService` / `PersonaSummarizerService` / `OverallSummarizerService`, and
`Prompts::ContextBuilder` folds the latest of each into `# CURRENT CONTEXT` every turn.
Each carries an in-world narrative (`summary_text`) plus an OOC steering side-channel in
`metadata` (`ooc_note` / `director_note` / `active_threads` / `real_world_facts`).

Also injected under CURRENT CONTEXT:

- **Ambient world state (live).** `ContextBuilder` reads one HASS composite template
  sensor (`sensor.glitchcube_world_state`, its `content` attribute) each turn — e.g. "It
  is 1:01 AM and dark out. The weather is partlycloudy, ~72°F…". Templated on the HASS side
  (source in `data/homeassistant/templates/glitchcube_world_state.yaml`) so it extends as
  devices come online, no Rails change. Fail-open.
- **`ooc_questions` probe.** The brain schema has an optional `ooc_questions` field where a
  persona can raise an out-of-character question (about its character, for a director, or for
  the project's programmer). **Collected only** — `LlmIntention#log_ooc_questions` logs it;
  nothing is wired to answer it. A smoke test to see what personas actually want to ask.

Dormant (reference only): `Memory` + `MemorySearchService`, and the old reflection/
`WorldState` design in [continuity.md](./continuity.md) (banner-flagged superseded).

Conversation history is a **rolling window across sessions** (`MessageHistoryBuilder`,
default 12 turns / 10 min, persona-scoped, soft session-break markers) — the cube
half-remembers recent people rather than resetting per conversation.
