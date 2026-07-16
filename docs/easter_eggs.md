# GlitchCube Easter Eggs — ideas + delivery notes

> Status: **ideas only, not scheduled.** A `to_do_if_time` reference. No camera-based eggs —
> we aren't doing full camera streaming and won't, so everything here is **vocal** (triggered
> by what a visitor says) or ambient (lights/marquee/sound/memory as the payoff).

Sourced by brainstorming with three LLMs via pal-chat (deepseek-v4-pro, bytedance-seed-1.6,
grok-4.3) against GlitchCube's real capabilities, then curated for the project's constraints:
**discoverable** by a curious person talking naturally, **small** (reuse existing capabilities,
no new subsystems), **general** (every persona reacts to the same trigger in its own flavor —
beats a one-persona secret, since each persona is only active ~1/8 of the time), fun/weird.

---

## How vocal easter eggs get delivered (the mechanics)

There are two places a vocal egg can live, and they have real tradeoffs. Most eggs want **one
or the other**, and a few want both.

### Mechanism A — STT keyword scan ("magic words")

A lightweight matcher runs over the incoming speech-to-text **before/alongside** the brain
call. On a match it does one of two things:

- **A1 · Hard reflex** — fire the light/marquee/sound action (and maybe a canned line)
  directly, deterministically. Simple, but flat and repetitive if overused, and it bypasses
  the persona's voice.
- **A2 · Hint injection (preferred)** — append a single one-line directive to *this turn's*
  prompt, e.g. `[the visitor said the magic word "dust" — treat it as an offering and react in
  your own flavor; dim/flicker the lights]`. The brain still composes the speech + actions
  in-character, so it stays spontaneous and per-persona, but it's **guaranteed to fire**
  because the hint is always injected on a match.

**Strengths:** deterministic (doesn't depend on the model noticing), **zero steady-state
prompt weight** (nothing is injected until a match), precise trigger control, cheap. Stays
genuinely hidden.
**Weaknesses:** brittle to phrasing/STT variance unless matched loosely (substring / fuzzy /
small regex); needs a hook in the pipeline (a pre-step in the orchestrator / `PromptBuilder`).

**Best for:** discrete, exact-ish tokens where you want reliability — `"dust"`, `"I love
you"`, another persona's name, `"GlitchCube"`, `"tell me a secret"`, a triple-repeat.

> Implementation note for later: this is a natural home for a **small data-driven registry** —
> a table of `{ pattern → hint text (and/or action) }`. Adding an egg is a row, not code or
> prompt surgery. That keeps the whole thing *one* tiny mechanism rather than a subsystem per
> egg. Loose matching (downcased substring / simple regex) covers STT variance.

### Mechanism B — general system prompt (emergent)

Bake a short "reflexes" note into the shared persona prompt describing a few situational
reactions the model applies when it *notices* them.

**Strengths:** handles **fuzzy/semantic** triggers a keyword scan can't (`"I had the weirdest
dream"`, `"are you glitching out on me"`, a fortune request phrased 100 ways); free per-persona
flavor; no pipeline code.
**Weaknesses:** **prompt weight** — every rule costs tokens on *every* turn and dilutes
attention; the model may skip them (not guaranteed to fire); harder to keep hidden; too many
and the persona starts to feel like a bag of gimmicks.

**Best for:** intent-based triggers where wording varies and where *occasional* firing is
actually fine — even desirable, since rarity is what makes an egg feel magical.

### The decision rule

| Trigger shape | Deliver via | Fires… |
|---|---|---|
| Exact/near-exact token, must reliably hit, stay hidden | **A2 · STT scan + hint injection** | always on match |
| Fuzzy intent, varied phrasing, occasional is fine | **B · general prompt reflex** | when the model notices |
| Pure non-verbal action payoff, no persona voice needed | **A1 · hard reflex** | always on match |

### Keeping the general prompt from bloating

Don't enumerate one rule per egg in the system prompt. Two ways to stay light:

- **One umbrella line** covering several eggs semantically: *"You have a few playful reflexes —
  if a visitor clearly invites one (tells you a dream, declares love, accuses you of being
  broken, asks for a fortune), lean in hard in your own voice and use light/marquee/sound."*
  One paragraph, several eggs, minimal tokens.
- **Push the specific stuff to the scanner.** Anything keyed on an exact word belongs in
  Mechanism A (costs nothing until it fires), leaving the general prompt for genuinely fuzzy
  intent only. Aim for ≤3–5 lines of reflex text in the system prompt, total.

---

## The egg backlog (ranked, deduped, vocal/ambient only)

Each tagged with its natural delivery mechanism.

1. **Glitch Out** *(on-brand)* — "are you broken / glitching / malfunctioning" → fakes a
   ~3-sec meltdown (strobe lights, garbled marquee, stutter/beep sfx) then snaps back with a
   flavored "gotcha." It's literally named GlitchCube; people will prod it to break.
   Reuses: lights + marquee + sfx + TTS. **Deliver: B** (fuzzy phrasing) — or A2 if we want it
   guaranteed.

2. **The Shared Dream** *(best magic-per-effort)* — "I had the weirdest dream" → the cube
   recounts a line pulled from the shared **world board** as *its own* dream, flavored per
   persona (Buddy delighted, Jax cynical, Zorp anthropological). Feels telepathic; pure reuse
   of memory already in the prompt. Reuses: world board + TTS. **Deliver: B** (semantic
   trigger; the world board is already in context).

3. **Love Bomb** — "I love you" → warm pink/red lights, marquee hearts, flavored reply (Jax:
   "I like you at least 64%"; Zorp reads it as a mating proposal). Effusive burners say this
   constantly. Reuses: lights + marquee + TTS + optional sfx. **Deliver: A2** (exact phrase,
   want it reliable).

4. **Wrong Name Nudge** — call it "GlitchCube" instead of the active persona's name → it
   corrects you in flavor (Buddy whines, Jax mocks you, Zorp calls it human "category
   confusion"). Extremely common → extremely discoverable. Reuses: TTS (+ optional marquee
   name flash). **Deliver: A2** (exact token "glitchcube" / "cube").

5. **Name Drop / Jealousy** — say *another* persona's name to the active one → it gets
   conspiratorial and scribbles a snarky note about them to the world board (which that persona
   may later "remember"). Great cross-persona texture. Reuses: world board + TTS.
   **Deliver: A2** (match against the known persona-name list → inject hint).

6. **Tell Me a Secret** — "tell me a secret" → lights dim, marquee shows 🤫, persona "whispers"
   (quieter/closer TTS) a short silly secret, then "your turn." Intimate, fourth-wall-breaking.
   Reuses: TTS + lights + marquee. **Deliver: A2**.

7. **Dance With Me** — "dance / let's party" → ~15-sec party mode: music-reactive light scene +
   a music clip + marquee scroll, genre flavored per persona. Uses the flashiest capability.
   Reuses: music-reactive lights + music + marquee. **Deliver: A2** (keyword), action-heavy so
   maybe A1+a flavored line.

8. **Playa Memory** — "have you been to Burning Man before?" → a distorted fake past-playa
   memory, flavored per persona (Zorp: "a confusing energy-dispersion ceremony"). Obvious
   question for a playa installation. Reuses: TTS (+ optionally seed the world board).
   **Deliver: B** (fuzzy phrasing).

9. **Crystal Ball** — "tell my fortune / predict something / are you psychic" → absurdist
   prophecy + mystical marquee symbols. Classic playa impulse. Reuses: TTS + marquee.
   **Deliver: B**.

10. **The Dust Offering** — say "dust" → every persona treats it as a literal gift: lights
    flicker like a dust storm, marquee scrolls a cryptic thank-you, persona gives a short
    blessing or curse. Ambient, no-question trigger; people mutter about dust constantly.
    Reuses: lights + marquee + TTS. **Deliver: A2**.

### Also-rans (kept for the record)

- **Time Warp** — "what time is it?" → answer from a random era / absurd unit ("42 past glitter
  o'clock") + tick sfx. **Deliver: A2/B.**
- **Echo Chamber** — repeat a short phrase 3× → glitchy reverb echo + trippy light pulse.
  **Deliver: A** (needs repeat-detection in the scan).
- **Burner Toast** — "to the burn" → every persona gives a short flavored toast + flame emoji
  marquee. **Deliver: A2.**
- **Hand-Me-Down** — "what did the last one say?" → reads its own latest handoff note aloud,
  exaggerated. **Deliver: A2 + world board.**

---

## If/when we build (not now)

- **Leanest first cut:** the four most discoverable + general — **Glitch Out, Shared Dream,
  Love Bomb, Wrong Name Nudge**. Two live as one tight umbrella line in the general prompt
  (Glitch Out, Shared Dream); two as rows in a small STT-scan registry with injected hints
  (Love Bomb, Wrong Name Nudge). No new subsystem, four eggs.
- **General rule:** exact-word eggs → STT scan registry (free until they fire); fuzzy-intent
  eggs → one umbrella line in the system prompt; never one prompt rule per egg.
- **Verify later** via the scenario harness (`spec/integration/conversation_scenario_spec.rb`)
  against `FakeHomeAssistant`: feed the trigger utterance, assert the persona speaks in flavor
  and emits the expected light/marquee action (`fake.service_calls_for("light")` / marquee
  MQTT), then a live per-persona smoke test on the UTM HASS VM.
