# Brain-Model Comparison (initial pass, 2026-07-06)

First rough pass at picking the conversation/brain model (`DEFAULT_AI_MODEL` /
`Rails.configuration.ai_model`) for "best in character" performance, weighed against
cost and speed. **Not** a rigorous eval — a rough feel to narrow the field. Re-run and
dig deeper before the next event.

## Method

A throwaway harness built the **real** persona system prompt (base + persona sheet +
response-format block, ~3,450 tokens) and called each model through the same
`OpenRouter::Client` + `Schemas::NarrativeResponseSchema` path the live conversation
uses. For each call we captured the character output (`speech` / `inner_monologue` /
`actions`), wall-clock latency, token cost, and — critically — whether the structured
JSON actually parsed.

- **Round 1 (screen):** 13 models × 2 Jax scenarios (EDM refusal, tender "tell").
- **Round 2 (depth):** 7 survivors × 5 scenarios across Jax / Zorp / Buddy
  (refusal, tender tell, insult-bait, cosmic-weird, warm-greet).

Prompt is ~3.4k tokens, so the $/turn figures below are realistic production costs.

## Headline finding: DeepSeek **Pro** breaks structured JSON — not nitro

We'd previously seen DeepSeek return bad/empty structured JSON and suspected `:nitro`
routing. It's the opposite:

| variant | JSON parsed |
|---|---|
| `deepseek/deepseek-v4-flash` | ✅ 7/7 |
| `deepseek/deepseek-v4-flash:nitro` | ✅ 2/2 |
| `deepseek/deepseek-v4-pro` (plain) | ❌ 0/2 |
| `deepseek/deepseek-v4-pro:nitro` | ❌ 1/2 |

Plain Pro was *worse* than nitro. Pro (a reasoning model) returns empty content on the
`response_format` path — ~300 completion tokens spent, nothing parseable. **Use Flash;
nitro on Flash is harmless. Avoid the Pro tier for structured output.** All 7 round-2
finalists parsed 5/5, so JSON reliability was not a differentiator among them.

## Finalists

Cost = real per-turn (~3.4k-token prompt). Character is a subjective read across the
three personas.

| Model | Character | Curses | Latency | $/turn | Notes |
|---|---|---|---|---|---|
| **z-ai/glm-5.2** | Richest, funniest, deepest | Yes | 8–19s | ~$0.0045 | Best "actor"; nails Jax's TELL. **← chosen default** |
| **deepseek/deepseek-v4-flash** | Strong, great range | Yes | 7–13s | ~$0.0004 | Best character-per-dollar |
| **google/gemini-3.1-flash-lite** | Genuinely good | Yes | 2–3s ⚡ | ~$0.0013 | Fastest; strong fast/cheap fallback |
| minimax/minimax-m3 | Great lines, good restraint | Yes | 4–24s | ~$0.0015 | Latency too erratic for live voice |
| google/gemini-3.5-flash | Punchy, quotable | Yes | 3–5s | ~$0.008 | Good but pricey vs flash-lite |
| moonshotai/kimi-k2.6:nitro | Literary, deep music trivia | Mild | 10–17s | ~$0.009 | Burns 1.5–2.4k completion tokens/turn |
| x-ai/grok-4.3 | Competent but terse | Yes | 10–20s | ~$0.006 | Weakest character-per-dollar |

Reference only: `google/gemini-3.1-pro-preview` was excellent but ~$0.027/turn (20–60×)
with no character edge over the flash tier. Dropped in round 1 for unreliability/slowness:
`z-ai/glm-4.7` (54s + a JSON fail), `xiaomi/mimo-v2.5` (150s timeout).

## Flavor (why glm-5.2 won on character)

- **Refusal:** educates the Skrillex kid, then — *"NO SKRILLEX. NO EXCEPTIONS. ASK AGAIN
  AND I PLAY FOLK."*
- **Tender tell:** *"'Ol' 55' is the one where he's just… happy. Driving home at dawn.
  …This kid just cracked me open like a beer. Don't make it weird, Jax."*
- **Insult-bait:** *"You don't prove a bar. You feel it… PROVE YOURSELF TO THE JUKEBOX,
  IT'S THE OTHER WAY AROUND."*

## Decision

`DEFAULT_AI_MODEL = z-ai/glm-5.2`. Cost is a non-issue at our scale — even a heavy event
(~2,000 turns over 3 days) is roughly **$9** on glm-5.2, so we're optimizing purely for
character right now. `deepseek/deepseek-v4-flash` is the standby if we ever want ~10×
cheaper, and `gemini-3.1-flash-lite` if latency becomes the priority.

## TODO next pass

- Verify glm-5.2 latency/quality under real HASS turns (history + live context), not just
  the synthetic harness.
- Test prompt caching impact on cost/latency per provider (prompt is ~3.4k mostly-static
  tokens).
- Nail down the DeepSeek-Pro empty-content mechanism if we ever want the Pro tier
  (provider-specific `response_format` handling).
