# GlitchCube — Revival Refactor Notes

**Status:** in progress · **Started:** 2026-06-22 · **Target:** working at a regional event in 2–4 months, path back to Burning Man

This is the durable record of the 2026 revival effort: what we learned from a deep-dive code review, what we decided to do about it, and why. It complements the working plan and is the place to update as decisions evolve. Read it before making structural changes.

---

## 1. What this system is

Rails 8 backend (Ruby 3.3.9, PostgreSQL 17 + PostGIS + pgvector) for an autonomous, multi-persona AI art-cube. Home Assistant (HASS) provides the ears, mouth, and hands (wake word, STT, TTS, device control, sensors); Rails is the brain (personas, memory, goals, decisions). Built in ~3 weeks for Burning Man 2024, never fully battle-tested, last touched Aug 2025.

Conversation path today: a custom HASS conversation component POSTs recognized speech to `POST /api/v1/conversation` → `ConversationNewOrchestrator` runs a 6-step pipeline (Setup → PromptBuilder → LlmIntention → ActionExecutor → ResponseSynthesizer → Finalizer) → returns speech text → HASS speaks it.

---

## 2. Headline decision: **refactor, not rewrite**

The Rails "brain" is sound and modular (clean 6-step orchestrator, decent ~0.85 test ratio, good tool registry + validation). The pain is concentrated in four seams, all fixable in place. A rewrite would throw away working persona/memory/goal/tooling systems for no structural gain. **We refactor.**

The single most important architectural change is how environment control is structured (see §4).

---

## 3. Deep-dive findings (the four problem seams)

### A. LLM pipeline — over-engineered for 2024 models
- `LlmService#call_with_tools` **discarded the caller's `model`** and random-sampled from a hardcoded pool every call (`app/services/llm_service.rb`). Non-deterministic, un-pinnable. *(Fixed — see §6.)*
- An ENV-flagged "two-tier" experiment (`TWO_TIER_TOOLS`) plus a per-domain agent fan-out: `ActionExecutor` split environment intents by keyword and delegated to `MusicAgentJob` + `HaAgentJob`, which called back into **HASS's own conversation agents** (`conversation.claude_conversation`, `conversation.jukebot`). Circular, latency-prone, and hard to test. This was the source of the original "parallel tool calls got glitchy" pain.
- Manual JSON "auto-healing" scaffolding. Note: the `open_router_enhanced` gem already does schema validation + healing well — we lean into the gem rather than hand-rolling.
- Dead code and very verbose logging in `LlmService`.

### B. HASS seam — drifted from current HASS, unclear source of truth
- The custom component (`data/homeassistant/custom_components/glitchcube_conversation/conversation.py`) is a thin HTTP proxy. It still uses `async_process` (soft-deprecated; HASS now prefers `_async_handle_message(user_input, chat_log)`) and returns one finished string, which **forfeits HASS 2025.7 streaming TTS** (adds perceptible speak-latency). It carries archaeology from the pre-Rails era ("Sinatra app" comments) and hardcoded values (`192.168.0.99`, `media_player.square_voice`, `cloud_say`, `en-US`, sound paths).
- The world-state trigger endpoint used `constantize` on attacker-controllable input. *(Fixed — see §6.)*
- **State ownership was never written down.** Persona lives in HASS (`input_select.current_persona`), conversation state in Rails, device state in HASS, world events flow HASS→Rails — but nothing documented who owns what, causing the "which code lives where" confusion. The whole HASS config is snapshotted in-repo under `data/homeassistant/`, which drifts from the live instance.
- Modern options worth adopting: HASS now has a built-in LLM tools/Assist API and an **MCP Server (2025.2)** that exposes device control + live context over a standard protocol.

### C. Burning Man hardcoding — blocks portability
- Persona prompts (`lib/prompts/personas/*.yml`), `data/goals.yml` (~20 BRC-specific goals: trash fence, thunderdome, art cars, MOOP…), and `config/persona_themes.yml` (`burning_man_quest` per persona) are BM-themed.
- All geography is BRC-specific: `data/gis/*.geojson` (radial/arc streets, trash fence, The Man), and hardcoded logic in `LocationContextService`, `Landmark`, `Street` (street_type `radial|arc`), `Boundary`. **Decision: keep geo — it's vital for the Burn — but make it profile-driven**, optional for a regional event.
- Memory infrastructure (pgvector) is event-agnostic and portable; only the *content* references BM.
- `PerformanceModeService` default prompts hardcode "Burning Man".

### D. Testability — can't exercise scenarios without the hardware
- No way to drive scenarios "fakely" while the cube sits still. One-off harness scripts are scattered in `scripts/*harness*`. `HomeAssistantService` is a singleton but 10 services call `HomeAssistantService.new` directly, bypassing it.

### Pre-existing debt discovered (baseline, not caused by this refactor)
- **20 failing specs at HEAD** in `spec/services/conversation_new_orchestrator/` — test-mock drift (e.g. mocks return a `Hash` where code calls `.content`; `ConversationLogger` call-ordering expectations). Baseline measured: `73 examples, 20 failures`.
- **`bin/rails zeitwerk:check` fails** on `Memory::ContextInjectionService`: the file `app/services/memory/context_injection_service.rb` declares `Services::Memory::ContextInjectionService` (extra `Services::` wrapper) — wrong for its autoload path. Hidden in dev/test by lazy loading; **would break production eager-load.**
- **Dead route namespace:** `/api/v1/home_assistant/*` maps to `Api::V1::HomeAssistant::HomeAssistantController`, which doesn't exist (404). The live endpoint is `/ha/...` (top-level `HomeAssistantController`).
- Orphans: `to_be_implemented/` (jobs + memory services, some duplicating `app/services/memory/`), `docs/deprecated/`, redundant `scripts/*harness*`, naming drift (`ConversationLog` in code vs `Conversation`/`Message` in docs), 33 tracked `.DS_Store` files.
- **Local env gotcha:** PostGIS/pgvector are built for PG17, `db/structure.sql` is PG17-format (`transaction_timeout`), so the project requires **PostgreSQL 17**. A PG16 server cannot load the schema or the extensions.

---

## 4. Target architecture

### Separation of concerns (the source-of-truth fix)
- **HASS = ears, mouth, hands** — wake word, STT, TTS, device actuation, raw sensor events.
- **Rails = brain** — persona, memory, goals/policy, decisions. The only place behavior logic lives and is versioned.

### Two-LLM conversation pipeline (the core change)

> **Partly superseded (2026-07-04).** The *brain* half holds. The *translator* half
> was replaced: the in-Rails `ToolCallingService`/`ToolExecutor` were retired to
> `deprecated/tool_calling/`, and tool-calling moved out to a HASS **action agent**.
> See `docs/conversation_flow.md` for the current design; the original plan is below.

- **Brain LLM** (`call_with_structured_output` + `NarrativeResponseSchema`): returns `speech_text` + a single **plain-English `environment_instruction`** ("turn the lights orange and play heavy metal") + inner state. Owns character/context.
- **Translator LLM** (`ToolCallingService`): converts that one instruction into precise, **validated** HASS tool calls (it already has a retry/validation loop), executed via `ToolExecutor` entirely inside Rails.

This replaces the per-domain fan-out and the circular HASS-agent delegation. **Not** 8 specialized agents — one brain, one translator.

### Speak-while-acting policy (resolves the glitchiness)
Always emit speech first; dispatch `environment_instruction` to a background job (`EnvironmentDirectorJob`) that runs the translator + execution. Never block speech on tool completion. Data the brain needs back (memory/RAG) stays synchronous; environment results surface next turn via the existing `pending_ha_results` deferral.

### Event portability (`EventProfile`)
An active profile (start: `config/event_profiles/{regional,burning_man}.yml`, `EVENT_PROFILE` env) supplies vocabulary, geography dataset, zone definitions, quest set, and persona prompt variables. Persona prompts and performance-mode prompts get templated. Geo stays but becomes profile-driven (regional = minimal/optional, burning_man = full BRC data).

### Fake harness (testability first)
Make `HomeAssistantService` injectable (`instance=` / `reset_instance!`) and add a `FakeHomeAssistant` backend serving scriptable entity/sensor/GPS/world state. Scenario fixtures drive the real orchestrator against the fake; an `/admin` simulator shows the brain→translator→tools chain. Migrate the 10 direct `.new` callers to `.instance`.

### HASS seam modernization (staged)
- **B1:** migrate the custom component to `_async_handle_message`/`ChatLog`; strip hardcoded IP/entities/lang into config. Regains barge-in + HASS-contract compliance.
- **B2 (only if latency is perceptible on-site):** stream speech deltas into `ChatLog` for 2025.7 streaming TTS.
- Consider HASS MCP Server for device control instead of bespoke REST.

---

## 5. Prioritized sequence

Reordered (2026-06-22) around three operating criteria: **(1) raise the safety net before touching deep behavior, (2) keep tests green and runnable throughout, (3) every chunk independently reversible/re-prioritizable.** The key insight: the original "Cleanup" workstream hid the most important work — a *trustworthy, fast test signal* — which is the precondition for everything else. So "Cleanup" is split into **E1 (safety net, first)** and **E2 (cosmetics, anytime)**.

1. **E1 — Trustworthy + fast baseline** *(do first)*: fix the `zeitwerk:check` namespace bug + add an `eager_load!` smoke spec; triage the 20 pre-existing failures to deterministic green (fix cheap mocks, mark brittle ones `pending`); tag slow/VCR specs so a fast unit subset runs constantly. Test/namespace-only → fully reversible. Without this you can't tell a regression from baseline noise.
2. **A1 — FakeHomeAssistant + first scenario**: in-memory fake injected via the `instance=` seam + canned-LLM helper + one end-to-end orchestrator scenario (doubles as a golden-master happy-path). Additive.
3. **B — Finish LLM pipeline**: model-role config, remove `TWO_TIER_TOOLS` + dead `CallAgent`, trim logging. Mostly deletions; shrinks the surface C/D reason about.
4. **A2/A3 — migrate the 10 `HomeAssistantService.new` callers to `.instance`; scenario fixtures + runner**. Per-file, incremental.
5. **C — EventProfile** *(most invasive; guard it)*: introduce `EventProfile.current` defaulting to a `burning_man` profile that **reproduces today's exact values**, route personas/goals/geo through it incrementally, `regional` profile last. Default behavior never changes until `EVENT_PROFILE` flips → suite stays green, reverts per-file. Protect with **golden-master**: snapshot current prompt/goal output, assert byte-identical after the layer is introduced.
6. **D — HASS component migration** *(separate artifact, last/parallel)*: `_async_handle_message`/`ChatLog`, strip hardcoded values; keep old component as rollback; streaming TTS only if latency warrants.
7. **E2 — cosmetics**, interleaved: remove `to_be_implemented/`, `docs/deprecated/`, redundant scripts; untrack `.DS_Store`; state-ownership table. **Defer/skip** the `ConversationLog`→`Conversation` rename (wide cosmetic blast radius) — document the canonical name instead.

**Golden-master vs fixing mocks:** the 20 failures are over-mocked unit tests asserting implementation; don't sink time fixing mocks that will be deleted. Golden-master earns its keep on the orchestrator happy-path (A1) and decisively in C (assert "no behavior change" while introducing the profile layer).

---

## 6. Progress log

| Date | Change | Verification |
|------|--------|--------------|
| 2026-06-22 | Standardized local dev/test on **PostgreSQL 17** (switched brew service from @16); dev + test DBs create/load cleanly with PostGIS + pgvector. | `db:schema:load` clean (27 tables) |
| 2026-06-22 | **Secured world-state trigger:** replaced `constantize` in `HomeAssistantController` and `Admin::WorldStateController` with an explicit allowlist (`WorldStateUpdaters::Registry`). | 5 request specs green |
| 2026-06-22 | **Rewired environment control to the two-LLM pipeline:** `ActionExecutor` now sends one `environment_instruction` (or legacy `tool_intents`, collapsed) to a single `EnvironmentDirectorJob` → `ToolCallingService` translator. Deleted `MusicAgentJob`, `HaAgentJob`, and the per-domain keyword routing. Added `environment_instruction` to `NarrativeResponseSchema`. | `action_execution_spec` green (12 ex); **no regressions** vs baseline (orchestrator 20 failures before and after) |
| 2026-06-22 | Fixed `LlmService#call_with_tools` so an explicitly passed `model` is respected (was always overwritten by a random sample). | — |
| 2026-06-22 | Added `.DS_Store` to `.gitignore`. | — |
| 2026-06-22 | **Test baseline triaged 280 failures → 0** (922 ex, 130 pending) via 6 bounded agents; fixed real bugs (RagSearch tool def, CubeData autoload); deleted ~45 dead specs + ~23 stale LLM cassettes (re-record TODOs). | full suite ×3, 0 failures |
| 2026-06-22 | **A1 harness:** `FakeHomeAssistant` + first end-to-end orchestrator scenario (golden-master happy path), no hardware/network. | scenario spec green |
| 2026-06-23 | **Gem refresh:** unpinned + `bundle update` → Rails 8.1.3, neighbor 1.2, solid_queue 1.4, etc. Removed unused gems (jbuilder, capybara, selenium-webdriver). Added do-it-right philosophy to CLAUDE.md. | 923 ex, 0 failures; zeitwerk clean |
| 2026-06-23 | **Pending backlog cleared to zero.** Fixed real bugs (GPS context merge, gps_spoofing test-env, blank perf session); added `exceed_query_limit` matcher (real N+1 test); backfilled specs for `FakeHomeAssistant` (54), `EnvironmentDirectorJob` (12), `WorldStateUpdaters::Registry` (16); deleted old-architecture/drifted/speculative specs (real_e2e two-tier, perf-mode wall-clock e2e, action-exec fan-out, GPS integration, cache/nil/coercion guards, flaky ObjectSpace). | **933 ex, 0 failures, 0 pending**; rubocop clean |
| 2026-06-23 | **Finished deprecating the two-tier path:** deleted `Tools::HomeAssistant::CallAgent` + `*_two_tier_mode` registry methods + `TWO_TIER_TOOLS` config; `ToolCallingService` calls `tool_definitions_for_persona`. | suite green |
| 2026-06-23 | **Docs cleanup (E2 start):** updated CLAUDE.md (models, brain→translator flow, gem branch); deleted `to_be_implemented/` (orphaned dupes of `app/services/memory/`), `docs/deprecated/{README,HARNESS_RESULTS,GLITCHCUBE_IMPROVEMENTS_PLAN}`, `docs/toolcall_implementation_plan.md`, `.aider` chat log; promoted `PRODUCTION_DEPLOYMENT`/`USAGE_EXAMPLES` out of `deprecated/`; bannered legacy harness README. | — |
| 2026-06-23 | **Confirmed CubeData autoload fix** (was the last OPEN HIGH bug, §6a). Sensor registry already lives in the model; spec exercises `read_sensor`/`write_sensor` with no manual `require`. | cube_data specs green (37 ex) |
| 2026-06-23 | **Finished Phase 2 (LLM polish).** Dropped the legacy `tool_intents` field end-to-end (schema, `ActionExecutor` fallback, `ContextualSpeechTriggerService`, `NarrativeConversationSyncService`, persona + base prompt YAML, dead `build_structured_output_instructions`); `delegated_intents` now reflects the dispatched `environment_instruction`. Made model **roles explicit** in config (`brain_model`/`translator_model`/`summarizer_model`); removed the legacy `default_tools_model` fallback; fixed the broken admin `primary_model`/`backup_models` reads. Trimmed `LlmService`/`ToolCallingService` logging (removed the full-raw-response dump + banner noise; details → debug) and deleted the dead `transform_openrouter_response` chain. Deleted orphaned two-tier cassettes. | conversation/LLM specs green (133 ex) |
| 2026-06-23 | **Memory integration (recall→store loop).** Proactive recall: `SystemContextEnhancer` injects recent high-importance memories each turn (no per-turn embedding). On-demand: brain `search_memories` results now surface to the next turn via `pending_query_results`. Store: brain flags `memories` in the schema → `Finalizer` enqueues `MemoryStoreJob` → `ConversationMemory` (async, clamps untrusted importance/type). | memory specs green |
| 2026-06-23 | **Phase 4 (in-repo): injectable clock.** `PerformanceModeService` takes a `RealClock`/`FakeClock` (mirrors the HASS `instance=` seam); rebuilt the deleted perf e2e smoke spec driven by virtual time (no wall-clock loop). Found+fixed a 30s-per-example HA-timeout in the job spec (unstubbed `send_conversation_response`). Migrated a `HomeAssistantService.new` caller to `.instance`. HASS **custom-component** migration (Python) deferred — needs a live HASS to verify. | perf specs green + fast (job spec 157s → 0.5s) |
| 2026-06-23 | **Standing test-hygiene: embeddings offline.** Global stub in `rails_helper` now neutralizes `upsert_to_vectorsearch` *and* `similarity_search` for all five pgvector models (was only Event/Summary write side) — no spec leaks a real OpenAI embedding call. | full suite, no embedding HTTP |
| 2026-06-23 | **E2 cosmetics:** retired the legacy `scripts/*harness*` benchmarks (built on the deleted two-tier path; superseded by the `FakeHomeAssistant` scenario spec); wrote `docs/ARCHITECTURE.md` (state-ownership table + pipeline + memory loop); settled the `ConversationLog` naming (keep it; documented as canonical). | — |
| 2026-06-24 | **Memory loop wired end-to-end.** `NarrativeResponseSchema` gained a `memories` array field; `Finalizer` now enqueues `MemoryStoreJob` (async, so embedding write never blocks speech — same speak-first policy as `EnvironmentDirectorJob`). `SystemContextEnhancer.build_relevant_knowledge_context` replaced its TODO placeholder with a real `MemoryRecallService.get_relevant_memories(limit: 3)` call — proactive recall now injects top memories into the system prompt each turn. `ResponseSynthesizer` threads `memories` and `environment_instruction` through the response hash. `ContextualSpeechTriggerService` migrated off `tool_intents` array to single `environment_instruction` (now consistent with the brain→translator pipeline). Deleted `build_structured_output_instructions` (dead `tool_intents`-era code) from `SystemPromptBuilder`. Deleted three stale VCR cassettes (~1 200 lines). New specs: `MemoryStoreJob` (51 ex), `ResponseSynthesizer` (34 ex), `SystemContextEnhancer` (30 ex), performance-mode e2e with `FakeClock` (end-to-end loop runs in virtual time). | suite green |
| 2026-06-26 | **qualspec quality infrastructure.** Added `gem "qualspec"` (github: estiens/qualspec 0.1.2). Built separate quality spec stack: `spec/quality_helper.rb` (VCR permissive, no HTTP blocking), `spec/support/quality_helpers.rb` (`run_brain_turn`/`run_translator` helpers with FakeHA + per-turn timing), `spec/support/qualspec_rubrics.rb` (3 custom rubrics: `:cube_persona`, `:environment_instruction_quality`, `:translator_result_quality`). Added `spec/quality/persona_quality_spec.rb` (7 ex: Buddy/Jax/Zorp — in-character, concise, env_instruction quality, Jax-vs-Buddy distinctiveness) and `spec/quality/translator_quality_spec.rb` (10 ex: 5 instruction types × judge + service_calls). Added `eval/glitchcube_personas.rb` standalone CLI for all-8-persona comparison with HTML report. **Not yet run against real OpenRouter** — first run is the next session's starting point. Decided FakeHA > live HASS for testing (state isolation); UTM live HASS reserved for pre-event manual smoke test. Stale docs deleted: `docs/PENDING_TEST_ANALYSIS.md`, `docs/light_tools_consolidation.md`. | syntax OK; normal suite unaffected |
| 2026-06-28 | **Continuity simplification — replaced the whole memory/goal/summarizer stack** (see [`continuity.md`](continuity.md)). Three pieces now: a short **world-state flat file** (`storage/world_state.md`, mirrored to `sensor.glitchcube_world_state`) injected every turn; **one** `ReflectionService`/`ReflectionJob` (every 30 min) that reads `Conversation.unreflected`, rewrites the world state, and saves discrete memories; and a plain **`Memory`** model (renamed from `ConversationMemory`: `summary`→`content`, `memory_type`→`category`, +`emotion`/`occurs_at`, no session FK) searched by `Tools::Query::MemorySearch` (plain Rails — keyword/category/`occurs_at`, **no embeddings**; `embedding` column kept for a possible lazy future). **Deleted:** `GoalService` + `goals.yml` + `persona_themes.yml` + `goal_monitor`, the hourly/intermediate/daily/consolidation summarizers + `ConversationSummarizerService`, `app/services/memory/*` (recall/extraction/context-injection), `MemoryStoreJob`, `rag_search`, `SystemContextEnhancer`, `Event`/`Person`/`Fact` models + admin CRUD + their routes, `burning_man` controller/routes, and the goal/world-state rake tasks. Removed `vectorsearch` from `Summary`. Schema dropped `goal_progress` + per-turn `memories[]`; `search_memories` is now `{query, category, timeframe}`. New specs: `Memory`, `WorldState`, `ReflectionService`, `MemorySearch`. | suite green |
| 2026-06-28 | **Renamed `ConversationNewOrchestrator` → `ConversationOrchestrator`.** It was always the only orchestrator; `New` was a dead qualifier from early development. Renamed the service file, the step-file directory, and all spec directories. Updated all references in controller, config, spec support, integration specs, and docs. | 760 ex, 0 failures |
| 2026-06-28 | **Docs update:** CLAUDE.md gains UTM HASS VM connection info (SSH `root@glitch.local` / `easytoremember`), expanded `FakeHomeAssistant` usage docs, and `FakeClock` usage. REFACTOR_NOTES §8 updated to reflect post-memory-refactor state. | — |
| 2026-06-28 | **Fixed qualspec quality spec loading:** removed manual `config.api_key=` call from `spec/quality_helper.rb` — qualspec reads `QUALSPEC_API_KEY` from env automatically; the explicit setter caused a `NoMethodError`. Both quality spec files now load and dry-run cleanly. | 16 quality examples dry-run clean |
| 2026-06-28 | **Resilience fix (speech-path graceful degrade).** `LlmIntention`'s rescue now returns a *successful* synthetic narrative (fallback speech, `continue_conversation: false`, empty `environment_instruction`) instead of a failure — so a brain-LLM/OpenRouter error no longer rolls back the turn or makes the cube silent; it speaks "I'm having trouble thinking right now…" and the turn persists. Error still logged loudly via `ConversationLogger`. Validation failures (nil/blank prompt/model — bugs) still fail loudly. `EnvironmentDirectorJob` already log-and-skips on HASS failure (no change needed). | llm_intention spec 30 ex; full suite 760 ex, 0 failures |
| 2026-06-28 | **Ran + recorded the quality specs live (first real OpenRouter run).** Removed the manual qualspec `api_key=`; added `QUALSPEC_API_KEY` to `.env` (qualspec's judge hits OpenRouter directly). Findings logged in §8. Surfaced: a missing built-in `:concise` rubric, a persona-bleed bug (Zorp answered "I am BUDDY"), over-long/over-swearing brain output, and a translator-harness gap (async tools enqueue `AsyncToolJob` so `FakeHA.service_calls` stays empty — translator works, assertion is wrong). | cassettes recorded under `spec/cassettes/qualspec/` |
| 2026-06-28 | **Quality-spec quick wins (harness fixes).** (1) Defined the `:concise` rubric in `qualspec_rubrics.rb` (it was referenced as a qualspec built-in but doesn't exist — was crashing "Rubric not found"; now produces real scores). (2) Fixed the translator harness: `run_translator` now wraps `execute_intent` in `perform_enqueued_jobs` (incl. `ActiveJob::TestHelper`) so the `:async` light/music tools actually execute against FakeHA — `service_calls` populates (5 failures → flaky-1). **Two real MODEL findings, left as failing signal (not forced green):** brain `google/gemini-3.5-flash` emits ~11-sentence replies (fails `:concise`, needs prompt/model tightening); translator `minimax/minimax-m3` lacks `function_calling` and *intermittently* emits no tool call — a poor translator choice. Persona-bleed skipped (Zorp likely being deleted). | translator 4-5/5; concise rubric resolves |
| 2026-06-28 | **Moved HASS YAML snapshots to `deprecated/`.** `data/homeassistant/` → `deprecated/homeassistant/`, `config/home_assistant/` → `deprecated/config_home_assistant/`, stray `app/services/gps/blah.yaml` → `deprecated/gps_scene_creator_automation.yaml`. Rails never loaded these (in-repo reference snapshot of live HASS config, long drifted); kept as copy-from examples. Added `deprecated/README.md`; updated two comment path refs in `ha_data_sync.rb`. The custom HASS component (`conversation.py`, Phase 4b) moved with it: `deprecated/homeassistant/custom_components/glitchcube_conversation/`. | app boots; suite green |
| 2026-07-04 | **"Amnesiacube" + tool-calling handed to HASS (supersedes §4's translator design).** Two big shifts landed on `refactor/strong_mvp_dev_branch`: (1) **Continuity removed** — deleted `ReflectionService`+job, `ReflectionSchema`, `MemoryStoreJob`, `MemoryRecallService`, memory extraction/context-injection, the summarizer stack, `GoalService`, and the `Event`/`Person`/`Fact` models+admin. Brain `NarrativeResponseSchema` is now `speech`/`inner_monologue`/`actions[]`/`continue_conversation` only; no world-state blob is injected. `Memory`/`WorldState` linger dormant. (2) **In-Rails tool stack retired** — `ToolCallingService`/`ToolExecutor`/`AsyncToolJob`/`ValidatedToolCall`/`ToolMetrics`/`Tools::*` moved to `deprecated/tool_calling/`; `EnvironmentDirectorJob` now hands the instruction to a HASS **action agent** (`hass_action_agent`) via `conversation_process`. Kept `Tools::Query::MemorySearch` as standalone `MemorySearchService`. Migrated the last tether (`ContextualSpeechTriggerService`). **Docs reconciled:** new `docs/conversation_flow.md`; `CLAUDE.md`/`ARCHITECTURE.md` updated; `continuity.md` banner-flagged superseded. | suite green (580 ex); zeitwerk clean |

---

## 6a. Real product bugs surfaced during test triage (2026-06-22)

The full-suite triage (gem switch exposed ~280 failures) was spec-only, but it surfaced genuine app bugs. Fixed inline where they blocked the refactor; the rest are tracked here.

- **FIXED — `Tools::Query::RagSearch.definition` returned a bare `Hash`** instead of an `OpenRouter::Tool` (every sibling returns a Tool). `LlmService.call_with_tools` does `tools.map(&:name)`, so any tool list including rag_search crashed — breaking `ToolCallingService` (the translator) in production-equivalent paths. Converted to `OpenRouter::Tool.define`. Verified all registry tools are now homogeneous.
- **FIXED (2026-06-23) — `CubeData` model autoload.** The sensor registry now lives in the model (`app/models/cube_data.rb`); the initializer only calls `CubeData.initialize!` in `after_initialize`, so Zeitwerk loads the class normally and `read_sensor`/`write_sensor`/`ha_service`/`available?` are present at runtime. `spec/models/cube_data_spec.rb` exercises `read_sensor`/`write_sensor` with no manual `require`.
- **FIXED (2026-06-23) — `Gps::GpsTrackingService#current_location`** the random-landmark fallback `return`ed *inside* the `Rails.cache.fetch` block, skipping the `LocationContextService` merge. The block now yields the value so context always merges.
- **FIXED (2026-06-23) — `GlitchCube.gps_spoofing_allowed?`** now honors `test?` as well as `development?` (and a dead duplicate `home_camp_coordinates` was removed).
- **FIXED (2026-06-23) — `CubePerformance` blank session id** (`session_id ||=` kept `""`) → now `session_id.presence || …`.
- **WONTFIX (2026-06-23, philosophy) — `format_time_duration` coercion** and **`PerformanceModeService` cache-read/write rescue + nil-session guard.** Both call sites of `format_time_duration` already guard `> 0`, and the cache/nil cases are speculative ("let it fail loudly"). Tests asserting the defensive behavior were removed rather than adding guards.

Also notable: `PersonaSwitchService` was gutted (now just ends conversations + sets the HASS persona — no goal handoff / theatrical sequence), and the proactive endpoint moved off the orchestrator to `ProactiveMessageService`. Several specs encoded the old behavior and were deleted.

## 7. Open decisions
- Streaming TTS depth (stop at B1, or invest in B2) — decide after measuring on-site latency.
- `EventProfile` storage: flat YAML (assumed) vs DB-backed (admin-editable).
- ~~Keep `ConversationLog` naming or migrate to `Conversation`/`Message`~~ → **RESOLVED (2026-06-23): keep `ConversationLog`** (rename has wide cosmetic blast radius, no functional gain). Documented as canonical in `docs/ARCHITECTURE.md`.
- ~~Whether to fix the `to_be_implemented/` memory services or delete them~~ → **DELETED (2026-06-23)**; they duplicated `app/services/memory/`. Memory *integration* is now **DONE** (see §8 item 4).

---

## 8. What's next (plan as of 2026-06-28)

**Foundation work is done.** The core refactor (LLM pipeline, memory/continuity, tooling, test infrastructure) is complete and the suite is green.

**Completed since last update (2026-06-28):**
- ✅ Continuity simplification — world-state + reflection + plain Memory (no goals, no multi-layer summarizers, no embeddings)
- ✅ `ConversationNewOrchestrator` → `ConversationOrchestrator` rename (cosmetic, it was always the only one)
- ✅ CLAUDE.md updated with UTM HASS VM info and FakeHomeAssistant docs

**Remaining work, in recommended order:**

### 1. Webhook request specs + world-state context setup (TOP priority)

The real testing need is **HASS-triggered events arriving as webhooks** (e.g. a motion
sensor change → POST to Rails → start a conversation / proactive moment). These are
ordinary request specs; the hard part is **setting up complex world-state context** so
we can assert behavior under specific conditions ("motion fires when it's night AND a
Sunday AND the cube is in low-power mode"). What we need:

- A test helper to seed `WorldState` content + relevant entity/sensor state + clock
  (time-of-day, day-of-week) for a request, then POST the trigger and assert on the
  response/side effects.
- This matters more than `FakeHomeAssistant` completeness right now — we care about
  what *Rails does when HASS pokes it*, not about faking HASS's own responses.
- Today's HASS→Rails entry points: `POST /ha/world_state/trigger` (→
  `WorldStateUpdaters::Registry`). A dedicated motion/proactive webhook may need to be
  added — design it alongside the spec.

### 2. Quality specs — reframe as MODEL quality, not persona-vs-persona (first run done)

The specs ran live (cassettes recorded). The **goal is to find the best/cheapest model**
that (a) stays in character and (b) emits correct environment commands — NOT to compare
personas to each other. To get there, qualspec should sweep **candidate models** against
a fixed persona/instruction set and report pass-rate + cost per model.

Harness quick-wins — **DONE (2026-06-28):**
- ✅ **`:concise` rubric** defined in `qualspec_rubrics.rb` (was crashing "Rubric not found").
- ✅ **Translator harness** now `perform_enqueued_jobs` so `:async` light/music tools
  execute against FakeHA and `service_calls` populates.
- ⏭️ **Persona bleed** (Zorp "I am BUDDY") — skipped; Zorp likely being deleted.

Real MODEL findings surfaced by the first run (left as failing signal, NOT forced green):
- **Brain `google/gemini-3.5-flash` is too verbose** — ~11-sentence replies, fails the
  `:concise` TTS criterion. Needs prompt tightening and/or a different model. A model
  sweep is the right tool to pick the cheapest one that stays concise + in character.
- **Translator `minimax/minimax-m3` is a weak tool-caller** — it lacks `function_calling`
  capability and *intermittently* emits no tool call at all (the `light_color` scenario
  flaked red then green on re-run). Strongly consider a different `TOOL_CALLING_MODEL`.

Next step to make this a real model sweep: parameterize the quality specs (or `eval/`)
over **candidate models** and report pass-rate + cost per model, rather than testing one
fixed brain/translator pairing.

### 3. FakeHomeAssistant audit (lower priority now)

Deferred — see §1. We need request-spec/world-state context more than HASS-response
fidelity. The HASS box (`glitch` / `100.79.82.74`, SSH `root/easytoremember`) stays reserved for
pre-event manual smoke testing.

### 4. Phase 3 — EventProfile portability (most invasive, defer)

Introduce `EventProfile.current` defaulting to a `burning_man` profile that
reproduces today's exact values, then route personas/goals/geo through it
incrementally; add a `regional` profile last. **Skip until 4–6 weeks before a
regional event.**

### 5. Phase 4b — HASS custom-component migration (on-hardware, deferred)

`_async_handle_message`/`ChatLog`, strip hardcoded values; streaming TTS only if
latency warrants. Do on actual Mac Mini hardware with a live HASS instance.
