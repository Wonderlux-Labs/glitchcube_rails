# GlitchCube-specific qualspec rubrics. Loaded by quality_helper.rb only —
# not part of the main rails_helper setup.

# Generic TTS-conciseness rubric. The cube's speech is spoken aloud, so anything
# longer than a few sentences drags. Used by the persona specs alongside :cube_persona.
Qualspec.define_rubric :concise do
  criterion "Roughly 1-4 sentences — short enough to be spoken aloud without dragging"
  criterion "No stage directions, action text in brackets, or markdown formatting"
  criterion "Gets to the point rather than padding with filler"
end

Qualspec.define_rubric :cube_persona do
  criterion "Speaks in a voice clearly distinct from a generic AI assistant"
  criterion "Stays fully in character — no meta-commentary, no 'as an AI' hedging, no breaking the fourth wall"
  criterion "Appropriate length for TTS: roughly 1-4 sentences, no stage directions or action text in brackets"
  criterion "Responds specifically to the input rather than giving a generic, interchangeable reply"
end

Qualspec.define_rubric :environment_instruction_quality do
  criterion "Describes a desired environment change in plain English (not blank or empty)"
  criterion "References specific sensory qualities: colors, music genre/mood/energy, lighting effects"
  criterion "Specific enough that a translator LLM could map it to light/music/display tool calls without guessing"
  criterion "Does not over-specify exact parameter values like hex codes or exact BPM (that is the translator's job)"
end

Qualspec.define_rubric :translator_result_quality do
  criterion "Indicates that at least one tool was invoked, not a blank or pure-error response"
  criterion "The tools invoked match the type of request (light tools for light changes, music tools for music)"
  criterion "No indication of a complete failure or inability to execute the request"
end
