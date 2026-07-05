# Deprecated — in-Rails tool-calling stack

This is the **old** environment-control machinery, retired when the cube moved to
delegating all tool-calling to a Home Assistant conversation agent.

Rails never loads anything in here — it lives outside `app/` and `lib/`, so Zeitwerk
ignores it. Kept as browsable reference, not as live code.

## What replaced it

The brain LLM now emits a single plain-English `environment_instruction`. That goes
to `EnvironmentDirectorJob` (`app/jobs/environment_director_job.rb`), which hands the
text straight to a HASS conversation agent via
`HomeAssistantService#conversation_process`. The agent owns *all* tool-calling —
picking devices, resolving "romantic lights" to RGB, retrying — and replies in
natural language, which the next turn's `PromptBuilder` folds back into context.

## What's here (was the old path)

- `app/services/tool_calling_service.rb` — the old in-Rails translator LLM
  (`execute_intent`: NL instruction → validated tool calls).
- `app/services/tool_executor.rb` — sync/async categorization + dispatch.
- `app/jobs/async_tool_job.rb` — async tool fan-out.
- `app/models/validated_tool_call.rb` — parsed/validated tool-call value object.
- `app/services/tool_metrics.rb` + `lib/tasks/tool_metrics.rake` — timing/telemetry.
- `app/services/tools/` — `Tools::Registry`, `Tools::BaseTool`, and every device tool
  (`lights/`, `music/`, `display/`, `effects/`, `modes/`, `communication/`) plus the
  orphaned `query/memory_search.rb`.
- `spec/…` and `spec/cassettes/…` — the matching specs and VCR cassettes.

## The one piece we kept (and moved forward)

`Tools::Query::MemorySearch` was extracted into a standalone service at
`app/services/memory_search_service.rb` (plain `Memory.search`, no tool machinery),
kept for a future background memory consolidator / deep-recall path. The copy in
`app/services/tools/query/memory_search.rb` here is the pre-extraction original.
