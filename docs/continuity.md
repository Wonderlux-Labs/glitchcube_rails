# Continuity: world state, reflection, and memory

How the cube keeps a sense of "what's going on" across conversations. Deliberately
small — three pieces, one background job, no embeddings, no goal system.

## 1. World state — the blob in every prompt

`WorldState` (`app/services/world_state.rb`) maintains a short, curated piece of
prose that is the cube's working continuity: recent recurring questions, the
current social vibe, anything it was just told about the event, how it's feeling.

- **Single source of truth:** a flat file at `storage/world_state.md`.
- **Mirror:** every write is also pushed to HASS `sensor.glitchcube_world_state`
  (attribute `content`) so it's visible on a dashboard. The file wins; a mirror
  failure never breaks a turn.
- **Injection:** `SystemPromptBuilder` prepends `WorldState.current` to every
  system prompt under "WHAT YOU CURRENTLY KNOW". Empty until the first reflection.
- **API:** `WorldState.current` (read) and `WorldState.replace(text)` (write +
  mirror). Reflection is the only normal writer.

Keep it short — it rides on every prompt, so it has to earn its tokens.

## 2. Reflection — the one background job

`ReflectionService` (`app/services/reflection_service.rb`), run by
`Recurring::Reflection::ReflectionJob` every 30 minutes:

1. Loads `Conversation.unreflected` (finished, `reflected_at` is nil; capped per run).
2. Builds transcripts from `ConversationLog`s and makes **one** structured LLM call
   (`Schemas::ReflectionSchema`, summarizer model) that returns a rewritten
   `world_state`, a one-to-three-sentence `summary`, and any `memories[]`.
3. `WorldState.replace(world_state)`.
4. Creates `Memory` rows (skipping near-duplicate content).
5. Archives a `Summary` row (type `reflection`) — condensed material for a *future*
   longer-interval trend job (not built yet; the seam is intentional).
6. Stamps `reflected_at` on the processed conversations.

This replaced the old hourly → intermediate → daily → consolidation summarizer
stack, the `goal_monitor`, and per-turn memory flagging.

## 3. Memory — plain rows, plain search

`Memory` (`app/models/memory.rb`) is intentionally not vector-backed:

| column | meaning |
| --- | --- |
| `content` | the memory, one sentence |
| `category` | one of `Memory::CATEGORIES` (`fact`, `event`, `person`, `preference`, `vibe`) — a placeholder taxonomy, refine as we learn what reflection emits |
| `importance` | 1–10 |
| `emotion` | optional — how the cube felt about it |
| `occurs_at` | optional datetime, for time-relevant `event` memories |
| `embedding` | retained but **unused** |

**Deep recall is opt-in.** The brain may emit `search_memories`
(`{query, category, timeframe}`); `MemorySearchJob` runs `Tools::Query::MemorySearch`,
which does a plain Rails query — `content ILIKE`, `category` filter, and an
`occurs_at` window (`upcoming`/`today`/`tomorrow`, e.g. "any events tomorrow?").
Results surface on the *next* turn via `conversation.metadata_json["pending_query_results"]`,
so deep recall never blocks speech.

### If plain search isn't enough

The `embedding` column and pgvector extension are still there. Reintroducing
semantic recall later is a single `after_save` on `Memory` that embeds `content`
(ideally lazily, in a background job over recently-created memories) plus a
`similarity_search` branch in `MemorySearch`. We deliberately did not build this
until plain search proves insufficient.

## What there isn't (anymore)

- No goal system (`GoalService`, `goals.yml`, `goal_monitor`) — a couple of static
  motivations live in each persona's prompt YAML instead.
- No `Event`/`Person`/`Fact` models — event-type info is a `Memory` with `occurs_at`.
- No per-turn or per-save embedding calls.
- No multi-layer summarizer jobs.
