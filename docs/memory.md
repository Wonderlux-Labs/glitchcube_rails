# Memory & continuity — the three-tier summarizer

How the cube keeps a sense of "what's going on" across conversations. This is the **live**
continuity system. It replaced the old reflection/`WorldState`/`Memory` design described in
the (superseded) [`continuity.md`](continuity.md).

Continuity is a **layered summarizer**, not per-turn memory. Three tiers write `Summary`
rows (`summaries` table) via `LlmService.call_with_structured_output`, and
`Prompts::ContextBuilder` folds the latest of each back into the `# CURRENT CONTEXT` block
of the system prompt every turn.

Each summary stores a narrative **plus a parsed `metadata` (JSON) blob**. The narrative is
in-world ("what the cube remembers"); the metadata is the **out-of-character (OOC) steering
side-channel**. Keeping them separate is the whole point — a `Summary` is not just one text
field.

## The three tiers

| Tier | Job / cadence | `summary_type` | Scope | Service | Schema → structured fields |
|---|---|---|---|---|---|
| **Running memory** | `Recurring::Memory::SummarizerJob`, every 10 min (`*/10 * * * *`) | `interaction` | cross-persona (`persona_id` nil) | `SummarizerService` | `summary`, `real_world_facts`, `ooc_note` |
| **Persona memory** | `PersonaSummarizerJob`, on persona switch (enqueued by `PersonaSwitchService` for the persona whose stint just **ended**) | `persona` | per persona (`persona_id` set) | `PersonaSummarizerService` | `summary`, `ooc_note` |
| **Big picture / director** | `Recurring::Memory::OverallSummarizerJob`, hourly (`5 * * * *`) | `overall` | cross-persona | `OverallSummarizerService` | `shared_narrative`, `active_threads`, `director_note` |

Schemas live in `app/services/schemas/{summary,persona_summary,overall_summary}_schema.rb`.
All three services feed the LLM a flat transcript rendered by `SummaryTranscript` (with
`═══ new session` markers + time-gap inferences so a bit repeated within one conversation
reads differently from the same bit landing once with several people).

## Storage

- The main narrative goes in the **`summary_text`** column (`summary` / `shared_narrative`).
- Everything else — `ooc_note` / `director_note` / `active_threads` / `real_world_facts`,
  plus bookkeeping like `folded_through_at` — goes in **`metadata`** (a JSON string column),
  read via `summary.metadata_json`.
- `persona` and `overall` are **versioned**: each run creates a new row reading the latest
  as its base, so the whole evolution is preserved. The latest row of a type is "the" one.

## Injection — `Prompts::ContextBuilder`

Every turn, `ContextBuilder` reads the latest of each tier and folds them into
`# CURRENT CONTEXT`, each blob capped at `MAX_BLOB = 900` chars. The exact labels the model
sees:

- **World state** (live HASS composite sensor `sensor.glitchcube_world_state` → `content`):
  `"Right now: …"`.
- **overall** → `"The bigger picture (how this whole event has gone so far): …"` +
  `"Still in the air (things visitors set up that you can pick up): …"` (`active_threads`) +
  `"A note to all of the cube's personas right now: …"` (`director_note` — cross-persona OOC
  steering every persona reads).
- **current persona's latest `persona`** →
  `"What you (<name>) remember from your recent time on the cube: …"` +
  `"A note to yourself: …"` (`ooc_note` — self-steering; personas visibly self-correct
  against their prior note).
- **latest `interaction`** → `"Recently (your running memory of the last little while): …"` +
  `"Things you've picked up about tonight: …"` (`real_world_facts`).

The interaction-tier `ooc_note` is **not** injected directly. It flows up into the hourly
overall summarizer, where persistent patterns are promoted into the `director_note` that
*is* injected. This is deliberate — a 10-minute sample is too twitchy to steer on directly;
the director is the considered channel. The trade-off is up-to-an-hour latency before a
running-memory observation reaches the personas.

## Steering in practice

The loop is real: a `director_note` like "play the failing light commands up as an in-world
'spectral glitch'" or "hold your persona longer" gets injected and personas follow it next
turn; a persona `ooc_note` like "you're staying on-model — keep the slow, smoky presence
going" reinforces character across a stint boundary (where raw history resets).

**Caveat:** summaries are built from the **transcript (intent), not execution results** — a
persona can "remember" an action (e.g. an announcement) that actually failed or timed out
downstream. Execution outcomes come back separately via
`conversation.metadata_json["pending_ha_results"]`, folded in the next turn by
`PromptBuilder#inject_previous_ha_results` (see [`conversation_flow.md`](conversation_flow.md)).

## History window (separate from summaries)

Raw transcript continuity is a rolling window built by `Prompts::MessageHistoryBuilder`:
the **current persona's** most recent turns, bounded by both a turn cap and a time window
(defaults **12 turns / 10 min**, `config/initializers/conversation_config.rb`), with soft
`SESSION_BREAK` markers where the visitor changes. It's persona-scoped, so on a switch the
window is naturally empty and cross-persona continuity comes only from the summaries above.

## Inspecting

The `/admin/summaries` screens browse all three tiers (timeline, per-persona, analytics).

## Dormant / reference only

- `Memory` (`app/models/memory.rb`) + `MemorySearchService` — plain-Rails deep-recall query,
  not wired into a turn.
- `urgent_question` (optional field on `NarrativeResponseSchema`) — opt-in deep-recall probe,
  **Phase 0 = log-only** (`LlmIntention#log_urgent_question`); no retrieval wired yet.
