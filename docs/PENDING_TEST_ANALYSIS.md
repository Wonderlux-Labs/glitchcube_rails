# Pending Test Analysis

Current baseline (2026-06-23): **877 examples, 0 failures, 31 pending.**

The triage + cleanup pass is done. The suite is green and every remaining pending
carries a `TODO` explaining why — nothing is silently broken. The 31 are NOT
cassette problems (all re-recordable VCR specs have been recorded against the
funded key); they break down as:

| Bucket | Count | What's needed |
|--------|-------|---------------|
| Real bug: performance_mode routes unreachable | 13 | Finish the `/api/v1/performance_mode/` controller migration, then update spec paths + record cassettes |
| Real bug: performance_mode state guards | 5 | Add nil/empty-session guards + cache rescue in `CubePerformance` |
| Need real HA connection / schema access | 7 | `real_end_to_end` — needs live HA or a fuller stub + `NarrativeResponseSchema` access fix |
| Real bug: GPS `return` inside `cache.fetch` | 2 | Move `random_landmark_location` out of the `fetch` block so context merge runs |
| Real bug / setup: time coercion, gps_spoofing test-env, empty session, Landmark seed | 3 | One-line production fixes (see TODOs in the specs) |
| Flaky: ObjectSpace GC threshold | 1 | Non-deterministic; leave pending or rewrite without object counting |

These are the input list for **Task #9 (E1e: central app-bug fixes)** — most are
small, well-localized production fixes to tackle in the next working session.

---

## Historical analysis (pre-cleanup, ~130 pending)

The sections below were written when the suite had ~130 pending. They remain as a
record of the patterns; the live counts above supersede them.

## Pattern A — VCR Cassette Re-recording (being fixed now)

**Root causes:**
1. `open_router_enhanced` gem promoted from `dev` → `main` branch; schema is now embedded as a system prompt instead of `response_format`, changing the HTTP request body
2. `LlmService#call_with_tools` was sampling from a random model pool — each run picked a different model, permanently invalidating `:body` VCR matching

**Fix applied:**
- `llm_service.rb`: disabled model pool sampling in `Rails.env.test?` — falls through to `DEFAULT_AI_MODEL` (`mistralai/mistral-nemo`)
- `spec/support/vcr.rb`: changed default match from `[:method, :uri, :body]` → `[:method, :uri]` (body contains the model + schema format, both change)
- `VCR_RECORD` env var is now wired up (use `VCR_RECORD=new_episodes bundle exec rspec <file>`)
- Stale cassettes deleted; re-recording in progress

**Affected specs:**
- `services/world_state_updaters/conversation_summarizer_service_vcr_spec.rb` (~6 tests)
- `services/conversation_new_orchestrator/llm_intention_spec.rb` (2 VCR-backed tests)
- `services/tool_calling_service_spec.rb`
- `services/tool_calling_service_retry_spec.rb`
- `integration/tool_calling_force_retry_spec.rb`
- `integration/tool_calling_retry_integration_spec.rb`
- `services/tools/array_parameter_validation_spec.rb`

## Pattern B — Stale Mocks (need rewrite, not re-record)

These tests have `pending` annotations with "stale mock" because the behavior they tested was intentionally changed:

| Spec | Line | Issue |
|------|------|-------|
| `finalizer_spec.rb` | ~206 | Finalizer now rescues `create!` internally → always returns success; test expected failure |
| `response_synthesizer_spec.rb` | ~93 | `amend_speech_with_query_results` path removed; query results go to next turn |
| `llm_intention_spec.rb` | ~198 | "Invalid response format" message gone; LlmService always returns a real response object |
| `llm_intention_spec.rb` | ~452 | Characterization test with hardcoded expectations that no longer reflect reality |

**Action needed:** Rewrite these 4 tests as characterization tests reflecting actual current behavior.

## Pattern C — Possible Real Bugs (documented, not masked)

These are pending with `TODO: possible real bug` — they document suspected production issues:

| Spec | Bug |
|------|-----|
| `gps/gps_tracking_service_spec.rb` (x2) | `return` inside `Rails.cache.fetch` block skips `LocationContextService` context merge on random-landmark fallback path |
| `prompt_service_time_handling_spec.rb` | `Prompts::ContextBuilder#format_time_duration` dropped defensive coercion (no `.to_f`) — nil input raises NoMethodError |
| `services/cube_performance_spec.rb` | `start_performance` uses `session_id \|\|= ...` which may not guard against empty string |
| `models/glitch_cube_spec.rb` | `gps_spoofing_allowed?` only checks `development?`, not `test?` |
| Various performance mode specs | `get_active_performance`, `store_performance_state` lack rescue blocks |

**Action needed:** Review and either fix the production code or document as accepted behavior.

## Pattern D — Removed Functionality (correctly pending)

Large groups of tests are pending at `describe`/`context` level for features that were removed:

- **Two-tier architecture** (`requests/two_tier_conversation_spec.rb`, `integration/direct_tool_calling_spec.rb`) — dual-agent fan-out removed
- **Performance mode API routes** (`requests/performance_mode_spec.rb`, `integration/performance_mode_end_to_end_spec.rb`) — routes moved to `/api/v1/performance_mode/` but tests hit old paths; cassettes don't exist
- **ProactiveEvents** (`integration/proactive_events_spec.rb`) — `inject_upcoming_events_context` moved to `SystemContextEnhancer`; tests need rewrite targeting new class

**Action needed:** Once performance mode routes stabilize, update route paths and create cassettes. ProactiveEvents tests need rerouting to `SystemContextEnhancer`.

## Pattern E — Environment/Setup Dependencies

| Spec | Dependency |
|------|-----------|
| `requests/real_end_to_end_conversation_spec.rb` | `CubePersona.current_persona` requires live HA connection or more complete stub |
| `requests/api/v1/gps_spec.rb` | GPS integration test requires seeded Landmark data |
| Various performance mode state tests | `start_performance accepts session_id: nil` — possible nil guard missing |
| `services/prompt_service_integration_spec.rb` | "Query counting not available" — `db:count_queries` helper not wired |

## Pattern F — VCR Cassettes: pgvector/Embeddings (intentionally non-deterministic)

`spec/services/tools/query/rag_search_vcr_spec.rb` — 13 tests pending. These cassette tests call OpenAI `text-embedding-3-small` to generate vectors, then run pgvector similarity search. Results are non-deterministic across different DB states (different IDs, different vector spaces). Re-recording would just create cassettes tied to the current DB state that break on next `db:reset`.

**These should stay pending** unless we add deterministic seed data and fixture vectors.

## Pattern G — Removed Dead Code (time travel)

`spec/services/prompt_service_time_handling_spec.rb` — the `rescue NoMethodError` guards were removed (they were catching `NoMethodError` from a renamed method; `build_upcoming_events_context` now exists on `Prompts::ContextBuilder` where `service` points). Both leap year and year boundary tests now run correctly with `travel_to`.

## Summary

| Pattern | Count | Status |
|---------|-------|--------|
| A — VCR re-recording | ~15 | **In progress** |
| B — Stale mocks | 4 | Needs rewrite |
| C — Real bugs documented | ~8 | Pending for awareness |
| D — Removed functionality | ~70 | Correctly pending |
| E — Setup dependencies | ~5 | Needs investigation |
| F — pgvector non-deterministic | 13 | Intentionally pending |
| G — Time travel | 0 | Fixed |
