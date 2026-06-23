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

---

## 6a. Real product bugs surfaced during test triage (2026-06-22)

The full-suite triage (gem switch exposed ~280 failures) was spec-only, but it surfaced genuine app bugs. Fixed inline where they blocked the refactor; the rest are tracked here.

- **FIXED — `Tools::Query::RagSearch.definition` returned a bare `Hash`** instead of an `OpenRouter::Tool` (every sibling returns a Tool). `LlmService.call_with_tools` does `tools.map(&:name)`, so any tool list including rag_search crashed — breaking `ToolCallingService` (the translator) in production-equivalent paths. Converted to `OpenRouter::Tool.define`. Verified all registry tools are now homogeneous.
- **OPEN (HIGH) — `CubeData` model never autoloads.** `config/initializers/cube_data_sensors.rb` defines the `CubeData` constant before Zeitwerk can load `app/models/cube_data.rb`, so the model's methods (`read_sensor`/`write_sensor`/`ha_service`/`available?`) are missing at runtime — only the initializer's `sensor_id`/`all_sensors` exist. Specs work around it with an explicit `require`. Production `CubeData.read_sensor` likely breaks. Needs an initializer/loader fix. **Still open — highest-value remaining bug.**
- **FIXED (2026-06-23) — `Gps::GpsTrackingService#current_location`** the random-landmark fallback `return`ed *inside* the `Rails.cache.fetch` block, skipping the `LocationContextService` merge. The block now yields the value so context always merges.
- **FIXED (2026-06-23) — `GlitchCube.gps_spoofing_allowed?`** now honors `test?` as well as `development?` (and a dead duplicate `home_camp_coordinates` was removed).
- **FIXED (2026-06-23) — `CubePerformance` blank session id** (`session_id ||=` kept `""`) → now `session_id.presence || …`.
- **WONTFIX (2026-06-23, philosophy) — `format_time_duration` coercion** and **`PerformanceModeService` cache-read/write rescue + nil-session guard.** Both call sites of `format_time_duration` already guard `> 0`, and the cache/nil cases are speculative ("let it fail loudly"). Tests asserting the defensive behavior were removed rather than adding guards.

Also notable: `PersonaSwitchService` was gutted (now just ends conversations + sets the HASS persona — no goal handoff / theatrical sequence), and the proactive endpoint moved off the orchestrator to `ProactiveMessageService`. Several specs encoded the old behavior and were deleted.

## 7. Open decisions
- Streaming TTS depth (stop at B1, or invest in B2) — decide after measuring on-site latency.
- `EventProfile` storage: flat YAML (assumed) vs DB-backed (admin-editable).
- Keep `ConversationLog` naming or migrate to `Conversation`/`Message`.
- ~~Whether to fix the `to_be_implemented/` memory services or delete them~~ → **DELETED (2026-06-23)**; they duplicated `app/services/memory/`. Memory *integration* (wiring memory into the conversation flow) is now tracked in §8 below.

---

## 8. What's next (plan as of 2026-06-23)

Foundation is done: green/fast suite, brain→translator pipeline live, fake harness in place, gems current, docs cleaned. Remaining work, in recommended order:

1. **Fix `CubeData` autoload (HIGH, small).** The one known production-breaking bug left (see §6a). `read_sensor`/`write_sensor` are missing at runtime because the initializer defines the constant before Zeitwerk loads the model. Move the sensor map into the model (or a plain module the initializer requires) so the class loads normally. Add a spec that calls `CubeData.read_sensor` without an explicit `require`.

2. **Finish Phase 2 (LLM pipeline polish).** The fan-out is gone; remaining: (a) drop the legacy `tool_intents` fallback in `ActionExecutor` once nothing emits it, (b) make the brain/translator/summarizer **model roles** explicit in config (today they all default to `gemini-3.1-flash-lite`), (c) trim verbose logging in `LlmService`/`ToolCallingService`. Optional: lightweight tool-call **timing metrics** (the one salvageable idea from the deleted `toolcall_implementation_plan` — only if we actually want latency data on-site; otherwise skip per "no speculative tooling").

3. **Phase 3 — `EventProfile` portability** (most invasive; guard with golden-master). Introduce `EventProfile.current` defaulting to a `burning_man` profile that reproduces today's exact values, then route personas/goals/geo through it incrementally; add a `regional` profile last. Snapshot current prompt/goal output and assert byte-identical after the layer lands. Keep geocoding — make it profile-driven, don't remove it.

4. **Memory integration** (was the core of the deleted `GLITCHCUBE_IMPROVEMENTS_PLAN`). `app/services/memory/` exists but isn't wired into the conversation flow, and `search_memories` from the brain isn't consumed end-to-end. Decide the minimal useful loop: recall relevant memories at prompt-build time + extract/store memories after a turn. Build only what a single event needs — not the full 6-job summarization pipeline that was just deleted.

5. **Phase 4 — HASS component migration** (separate artifact, last/parallel). `_async_handle_message`/`ChatLog`, strip hardcoded values; rebuild a **fast** end-to-end smoke test against a dev HASS instance (the deleted `real_end_to_end`/perf-mode e2e specs should come back here — but driven by an **injectable clock** in `PerformanceModeService` so they don't loop against wall-clock). Streaming TTS only if latency warrants.

6. **E2 cosmetics, anytime.** Reconcile/retire the stale `scripts/*harness*` benchmarks into the `FakeHomeAssistant` scenario harness; write the state-ownership table (`docs/ARCHITECTURE.md`); revisit the `ConversationLog`→`Conversation` rename decision.

**Standing test-quality follow-up:** a real OpenAI embedding call fires during the suite (rag_search path) — gate it behind a cassette/stub so the suite stays offline and fast.
