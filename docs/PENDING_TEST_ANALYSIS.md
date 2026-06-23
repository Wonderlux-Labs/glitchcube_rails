# Pending Test Analysis

Current baseline (2026-06-23): **933 examples, 0 failures, 0 pending.**

The pending backlog is fully cleared. Every one of the previous 31 pending was
resolved by exactly one of three actions, chosen per the project philosophy (art
project — fix at the root, no speculative defensive code):

### Production bugs fixed (real fixes)
- **GPS `return` inside `Rails.cache.fetch`** (`gps_tracking_service.rb`) — the
  random-landmark fallback used `return`, bailing out of the method and skipping
  the `LocationContextService` context merge. Restructured the block to *yield*
  the value so the merge always runs.
- **`gps_spoofing_allowed?`** (`glitch_cube.rb`) — now honors `test?` as well as
  `development?` (and removed a dead duplicate `home_camp_coordinates` def).
- **`CubePerformance` blank session id** — the five entry points used
  `session_id ||= …`, which keeps an empty string verbatim. Switched to
  `session_id.presence || …` so blank falls back to a generated id.

### Shared spec helper added
- **`exceed_query_limit` matcher** (`spec/support/query_limit_matcher.rb`) — wires
  up the N+1 query-count assertion the Event-scope test wanted; the test now runs
  for real (asserts the scope chain resolves in a single query).

### New code given specs (was previously untested)
- `spec/services/fake_home_assistant_spec.rb` (54 ex)
- `spec/jobs/environment_director_job_spec.rb` (12 ex)
- `spec/services/world_state_updaters/registry_spec.rb` (16 ex, security allowlist)

### Tests removed (testing removed/old behavior, speculative guards, or unsalvageable)
- `spec/requests/real_end_to_end_conversation_spec.rb` — tested the **old**
  two-tier schema (`tool_intents`) + deleted `tool_definitions_for_two_tier_mode`
  and needed live HA. The Phase-4 live smoke test will be rebuilt against the
  brain→translator pipeline.
- `spec/integration/performance_mode_end_to_end_spec.rb` — every example drove
  `run_performance_loop`, which loops against wall-clock `@end_time` while `sleep`
  is mocked short (~4 min for 3 tests), and had drifted (no logs / interrupt 404).
  Redundant with the fast `performance_mode_spec.rb` request spec + job/service
  specs. Rebuild needs an injectable clock in `PerformanceModeService`.
- Action Execution "Full Action Execution Flow" — mocked the removed
  `tool_intents`/per-domain-async fan-out.
- GPS "with real data (integration test)" — fought its own `.new` stub, expected a
  `'spoofed'` source the code never emits; covered by the unit spec.
- Speculative-guard tests dropped per philosophy ("let it fail loudly"):
  performance_mode cache-write/read rescue, nil-session reject, corrupted-cache→nil,
  session-reuse guard (already enforced at the controller), and
  `format_time_duration` nil/negative/string coercion (both call sites guard `> 0`).
- Flaky `ObjectSpace.count_objects` memory test — non-deterministic, no signal.

### Deprecated production code deleted
- `app/services/tools/home_assistant/call_agent.rb` (orphaned `call_ha_agent`).
- `tools_for_two_tier_mode` / `tool_definitions_for_two_tier_mode` /
  `two_tier_mode_enabled?` from `Tools::Registry`; `tool_calling_service.rb` now
  calls `tool_definitions_for_persona`; `two_tier_tools_enabled` config removed.

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
