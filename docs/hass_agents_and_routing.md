# HASS-side agents & action routing — decision record

A map of how the HASS-side conversation agents are wired today, and **which ecosystem moves
(local models, coordinator/multi-agent routing, MCP, HASS-side memory) are worth testing,
for which problems, and when.** Written while the cube still exposes little to HASS and the
single action agent is doing fine — so this is a "consult when devices are hooked up" note,
not a to-do list. Nothing here is committed to; the point is that we can defer all of it
cheaply.

## Current state (two opposite-direction agent flows)

Don't conflate them. See also [`ARCHITECTURE.md`](ARCHITECTURE.md) and
[`conversation_flow.md`](conversation_flow.md).

- **Visitor → Rails (voice agents).** A custom HASS component `glitchcube_conversation`
  (`data/homeassistant/custom_components/glitchcube_conversation/`) — a **thin proxy, not an
  LLM** — POSTs recognized speech to Rails `/api/v1/conversation` and speaks the reply. The
  live agent bound to the persona pipelines is `conversation.glitch_cube_neon`, **shared**
  across all personas; the `automations.yaml` Persona Switcher swaps the Assist *pipeline*
  (TTS voice), not the agent.
- **Rails → HASS (action agent).** Rails hands the brain's flattened action instruction to a
  **separate** HASS conversation agent, `conversation.google_gemini_flash_latest` (Google
  Gemini Flash), via `EnvironmentDirectorJob` → `HomeAssistantService#conversation_process`
  → `POST /api/conversation/process {text, agent_id, conversation_id:"cube_env_<id>"}`
  (speak-first, act-async; the reply is folded back next turn via `pending_ha_results`).

The action agent's **prompt and integration config live inside the HASS box** (Google
Generative AI config entry), *not* in this repo. In the repo, the action agent is only a
default id string: `config/initializers/config.rb:22`
(`HASS_ACTION_AGENT`, default `conversation.google_gemini_flash_latest`).

## Script surface — fuzziness is pushed down on purpose

`data/homeassistant/scripts.yaml` (mostly DEV mocks writing to `input_text` sinks today —
"wire up real behavior later"):

| Channel | Script / control | Param surface | Interpretation needed |
|---|---|---|---|
| jukebox | `play_music_on_jukebox` (real) | `query:str`, `queue:enum` | minimal — Music Assistant does fuzzy match + player/provider selection |
| mood_music | `play_mood_music_dev` | `query:str` | minimal — MA resolves a vibe/track phrase |
| sound_efx | `play_sound_effect_dev` | `effect:enum(8)` chime/tada/sad trombone/siren/airhorn/record scratch/crickets/drumroll | none — closed-set classification |
| announcement | `loudspeaker_announcement` | `message:str` (+ unused chime bool) | none — pass-through |
| marquee | `set_marquee_text_dev` | `message:str`, `color:str(name)`, `blink:bool(unused)` | none/minimal — name, not RGB |
| switches | `input_boolean` / `input_button` | boolean / trigger | none |
| lights | **no wrapper** — `light.cube_cube_voice_led_ring` via direct `light.*` | hs_color + brightness | **the only fuzzy one:** color-name→HSV |

The HSV→name reverse map already exists in
`templates/glitchcube_world_state.yaml:49-57`, so a name→value table/script is trivial.

## Two properties that make deferral cheap (the headline)

1. **Brain actions are already structured.** `Schemas::NarrativeResponseSchema` returns a
   list of `{action_name, description}`; the *only* lossy step is the join in
   `ActionExecutor#environment_instruction`
   (`app/services/conversation_orchestrator/action_executor.rb:34-39`). Per-channel routing
   later = route on `action_name` *before* that join. Small, localized.
2. **The action agent is one env var over a generic interface.** Swapping in a local
   Ollama-backed conversation agent, or a HASS-side coordinator, needs **zero Rails code** —
   point `HASS_ACTION_AGENT` at the new entity and A/B it.

## Decision map — problem → option → verdict / trigger

| Problem you might hit | Option | Verdict & trigger to revisit |
|---|---|---|
| Action latency; want the change to land *with* the words | Fast **local model** (Ollama on M1) as the action agent; maybe inline pre-speech | **Highest-value experiment, not yet.** Brain is already 8–19s and speak-first/act-async hides action-agent latency, so inline only matters if speech must accurately reflect a device change. Trigger: devices live → A/B a local agent via `HASS_ACTION_AGENT`, measure accuracy + latency vs Gemini Flash. Zero-code. |
| Trivial channels (enum sound_efx, boolean switches, pass-through announcement/marquee) | **Skip the LLM** — deterministic dispatch (or tiny local classifier); reserve an LLM only for fuzzy channels | **Most aligned direction.** Scripts take simple params and the brain already emits structured actions, so deterministic channels need no model. Trigger: wiring real hardware — add a color-name→HSV light script first, then decide per channel. |
| A specific device is flaky once wired | **Coordinator** (`conversation.process` fan-out) / multi-agent per domain | **Not a reliability fix.** Hardware flakiness needs scripts + the existing `pending_ha_results` error loop (already folds failures back to the brain; the summarizer `director_note` plays them up in-world). Multi-agent only pays off if channels develop *divergent* prompt/model needs. |
| Want routing (some actions → fast/local, some → capable/cloud) | **Rails-side routing** (on `action_name`) or **HASS-side coordinator** | **Premature; foundation already there.** Prefer Rails-side routing (Rails owns the split) unless you specifically want HASS to own fan-out. |
| Semantic recall of people/preferences | **HASS-side memory** (`ha-ai-memory`, PERMEAR, Graphiti/Neo4j) | **Skip — fragments memory.** Rails already owns continuity (three-tier summarizer, see [`memory.md`](memory.md)) and has a dormant `Memory` + pgvector + `MemorySearchService` + `urgent_question` probe to revive. Keep one source of truth. |
| Cube answering world questions (weather/schedule/web) | **MCP servers on the action agent** | **Doesn't fit the split.** Knowledge is the *brain's* job; the action agent is a device executor. Adding knowledge tools to the executor muddies the boundary. |
| Complex multi-service agentic loops | **n8n / webhook-conversation** | **Redundant** — Rails already *is* the orchestration layer. |

## Guiding principle

Keep pushing fuzziness **down** into scripts / Music Assistant / closed enums. Every channel
made simple-param shrinks the action agent's required intelligence toward "small local model
or deterministic dispatch" — which is what unlocks local, cheap, offline-resilient,
low-latency execution. The single cleanup that finishes the job (when lights are wired): a
`set_cube_light` script taking a **color name**, doing name→HSV in Jinja (mirror the reverse
map in `world_state.yaml:49-57`). After that, *every* channel is simple-param.
