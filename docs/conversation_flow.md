# Conversation & action flow (current)

High-level map of what happens when someone talks to the cube, and the class names
we actually use today. If you read one doc before touching the conversation path,
read this one. For the state-ownership table see [ARCHITECTURE.md](./ARCHITECTURE.md).

## The two HASS-side agent roles

Home Assistant owns all audio and all device control. There are **two distinct
kinds of HASS conversation agent**, and keeping them straight is the whole point:

1. **Persona voice agents (visitor-facing).** One HASS conversation agent /
   pipeline **per persona**, each wired to that persona's **TTS voice**. The visitor
   only ever talks to the *active* persona's agent. This agent does the wake word,
   STT (speech→text), and TTS (text→speech) — it hears the visitor and later speaks
   the reply *in that persona's voice*. It does **not** decide what to say; it hands
   the recognized text to Rails.

2. **The action agent (never visitor-facing).** A single, separate HASS
   conversation agent (`Rails.configuration.hass_action_agent`, default
   `conversation.google_gemini_flash_latest`) with the HASS **Assist API + the
   cube's entities exposed**. It never speaks to a visitor. Its only job is to take
   a plain-English instruction ("turn the lights orange and play heavy metal") and
   figure out the **actual HASS service/function calls** — picking entities,
   resolving colors, retrying — then report back in natural language. HASS owns
   tool-calling here; Rails no longer does.

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
   4. ActionExecutor      flatten actions[] → one plain-English           │
                          instruction; EnvironmentDirectorJob             │
                          .perform_later (speak-first, act-async)         │
   5. ResponseSynthesizer package speech + persona TTS voice              │
                          (CubePersona#tts_voice)                         │
   6. Finalizer           persist ConversationLog, tokens/cost,           │
                          HASS-formatted JSON                             │
   ▼ (returns immediately — does NOT wait on the action agent) ──────────┘
HASS speaks the reply in the active persona's voice
```

Meanwhile, dispatched in the background:

```
EnvironmentDirectorJob#perform
   │  HomeAssistantService#conversation_process(
   │     text: instruction,
   │     agent_id: Rails.configuration.hass_action_agent,
   │     conversation_id: "cube_env_<conversation_id>")   # stable per cube-conversation
   ▼
ACTION AGENT (HASS)  decodes → real service/tool calls → executes → NL reply
   │
   ▼
store on conversation.metadata_json["pending_ha_results"]
   │
   ▼
NEXT turn, step 2: PromptBuilder#inject_previous_ha_results folds the agent's
reply (or error) back into the brain's context, so the cube knows what actually
happened and can own its own failures instead of hallucinating success.
```

## Why speak-first / act-async

Speech is returned to HASS **immediately**; the action agent runs while the persona
voice is being read aloud. Device changes therefore land a beat after the words,
and their result is available by the next turn — never blocking speech on
tool completion. Two separate `conversation_id`s are in play: the visitor session,
and a stable `cube_env_<id>` so the action agent keeps its own running context of
what it has already done this cube-conversation.

## Class / responsibility quick reference

| Piece | Class / location | Role |
|---|---|---|
| HTTP entry | `Api::V1::ConversationController#handle` | Parse HASS payload, call orchestrator, format reply for HASS |
| Orchestrator | `ConversationOrchestrator` | The 6-step turn pipeline |
| Prompt assembly | `ConversationOrchestrator::PromptBuilder`, `Prompts::SystemPromptBuilder` | System prompt + history; folds in last turn's action results |
| Brain LLM call | `ConversationOrchestrator::LlmIntention` + `LlmService.call_with_structured_output` | One structured narrative call |
| Brain output shape | `Schemas::NarrativeResponseSchema` | `speech`, `inner_monologue`, `actions[]`, `continue_conversation` |
| Action dispatch | `ConversationOrchestrator::ActionExecutor` | Flatten `actions[]` → one instruction, enqueue the job |
| Action → HASS | `EnvironmentDirectorJob` → `HomeAssistantService#conversation_process` | Hand instruction to the action agent |
| Result carry-over | `conversation.metadata_json["pending_ha_results"]` ← job; → `PromptBuilder#inject_previous_ha_results` | Action outcome surfaces next turn |
| Speech + voice out | `ConversationOrchestrator::ResponseSynthesizer`, `CubePersona#tts_voice` | Speech text + persona TTS voice/language |
| Persona resolution | `CubePersona.current_persona` (HASS `input_select.current_persona`, cached 30 min) | Which persona is active |

## What is NOT in this flow anymore

The old **in-Rails tool stack** (`ToolCallingService`, `ToolExecutor`,
`AsyncToolJob`, `Tools::Registry` + device tools, sync/async tool_type) was retired
— it now lives under `deprecated/tool_calling/` (see its README). The action agent
replaced it wholesale; Rails emits plain English and HASS does the tool-calling.

The cube is also currently **"amnesiac"**: reflection, per-turn memory recall/flagging,
deep memory search, and the multi-layer summarizers were removed. The brain schema
carries no memory fields, and no continuity blob is injected into the prompt today.
`Memory` and `MemorySearchService` still exist but are **dormant** (nothing writes or
reads them in the turn) — kept for when we re-introduce continuity. See the banner in
[continuity.md](./continuity.md).
