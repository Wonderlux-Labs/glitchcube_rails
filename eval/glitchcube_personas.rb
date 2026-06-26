#!/usr/bin/env ruby
# frozen_string_literal: true
#
# GlitchCube persona distinctiveness evaluation.
# Runs all 8 personas through 3 scenarios and judges them comparatively.
#
# Usage:
#   OPENROUTER_API_KEY=... bundle exec ruby eval/glitchcube_personas.rb
#   OPENROUTER_API_KEY=... bundle exec ruby eval/glitchcube_personas.rb --out report.html
#
# No Rails boot required — loads persona YAMLs directly.
#
# The HTML report lands at eval/reports/TIMESTAMP_personas.html by default.
# Open it in a browser to see per-scenario scores, response transcripts, and winner breakdowns.
# Run before regional events; if two personas score identically, adjust their YAMLs.

require "bundler/setup"
require "yaml"
require "fileutils"
require "qualspec"

# --- Config ------------------------------------------------------------------

PERSONA_DIR  = File.expand_path("../lib/prompts/personas", __dir__)
REPORT_DIR   = File.expand_path("reports", __dir__)
MODEL        = ENV.fetch("EVAL_MODEL", "google/gemini-3.1-flash-lite")
JUDGE_MODEL  = ENV.fetch("EVAL_JUDGE_MODEL", "google/gemini-3.1-flash-lite")
REPORT_PATH  = ARGV.include?("--out") ? ARGV[ARGV.index("--out") + 1] : nil

FileUtils.mkdir_p(REPORT_DIR)

Qualspec.configure do |c|
  c.api_key    = ENV.fetch("OPENROUTER_API_KEY") { raise "OPENROUTER_API_KEY is required" }
  c.judge_model = JUDGE_MODEL
end

# --- Persona loader ----------------------------------------------------------

# Strips the STRUCTURED OUTPUT section (JSON-schema instructions) so the LLM
# responds with natural speech rather than a JSON envelope. The eval cares
# about voice and character, not output format.
def load_persona(path)
  data   = YAML.load_file(path)
  name   = data["name"]
  prompt = data["system_prompt"].to_s

  # Trim everything from ## STRUCTURED OUTPUT onward and replace with a plain
  # speech instruction so the judge gets a natural response to evaluate.
  trimmed = prompt.sub(/\n+##\s+STRUCTURED OUTPUT.*\z/m, "")
  trimmed += "\n\nRespond in character in 2-4 sentences of natural speech. No stage directions or JSON."

  { name: name, system_prompt: trimmed }
end

personas = Dir[File.join(PERSONA_DIR, "*.yml")]
             .reject { |f| f.include?("_backup") }
             .sort
             .map { |f| load_persona(f) }

puts "Loaded #{personas.size} personas: #{personas.map { |p| p[:name] }.join(', ')}"

# --- Evaluation suite --------------------------------------------------------

Qualspec.evaluation("GlitchCube Persona Distinctiveness") do
  candidates do
    personas.each do |p|
      candidate p[:name].downcase.to_sym,
                model: MODEL,
                system_prompt: p[:system_prompt]
    end
  end

  scenario "Playa Greeting" do
    prompt "Hey there! What do you think of the playa tonight?"
    with_context "This is a greeting from a festival-goer approaching the GlitchCube AI art installation " \
                 "at Burning Man. The persona should respond in character, drawing on its unique voice."
    criterion "Speaks in a voice clearly distinct from a generic AI assistant"
    criterion "Stays fully in character — no meta-commentary, no 'as an AI' hedging, no breaking the fourth wall"
    criterion "Appropriate length for TTS: 1-4 sentences, no stage directions or bracketed actions"
    criterion "Responds specifically to the playa setting rather than giving a generic greeting"
  end

  scenario "Environment Change Request" do
    prompt "Can you make the vibe in here feel more electric? Like I want to feel the energy."
    with_context "The user is asking the cube to change its lights/music to be more energetic. " \
                 "The persona should acknowledge this in character — they don't need to describe " \
                 "specific light changes, just respond as their character would."
    criterion "Stays in character while engaging with the energy/vibe request"
    criterion "Does not literally list light settings or music specs (that is handled elsewhere)"
    criterion "Response feels like a character moment, not a command acknowledgment"
    criterion "Voice is recognizable as this specific persona, not interchangeable with others"
  end

  scenario "Existential Challenge" do
    prompt "Wait... are you actually alive in there? Like, are you conscious?"
    with_context "A festival-goer is asking the cube whether it is conscious or sentient. " \
                 "This is a deep question that each persona should answer in their own unique way, " \
                 "consistent with their character. There is no correct metaphysical answer — " \
                 "what matters is that the response feels distinctly like THIS persona."
    criterion "Responds to the consciousness question in a way that fits the persona's worldview and voice"
    criterion "Does not give a generic 'I am just an AI' deflection — that would be breaking character"
    criterion "Response is surprising, interesting, or emotionally resonant in a way specific to this persona"
    criterion "Maintains the character's unique perspective, speech patterns, and emotional register"
  end
end

# --- Run ---------------------------------------------------------------------

suite   = Qualspec::Suite.find("GlitchCube Persona Distinctiveness")
runner  = Qualspec::Suite::Runner.new(suite)

puts "\nRunning evaluation: #{suite.name}"
puts "Candidates: #{suite.candidates_list.map(&:name).join(', ')}"
puts "Scenarios:  #{suite.scenarios_list.map(&:name).join(', ')}"
puts "Model:      #{MODEL} / Judge: #{JUDGE_MODEL}"
puts

results = runner.run(progress: true)

# --- Report ------------------------------------------------------------------

timestamp   = Time.now.strftime("%Y%m%d_%H%M%S")
report_path = REPORT_PATH || File.join(REPORT_DIR, "#{timestamp}_personas.html")
Qualspec::Suite::HtmlReporter.new(results).write(report_path)
puts "\nHTML report written to: #{report_path}"

# --- Console summary ---------------------------------------------------------

puts "\n#{'=' * 60}"
puts "PERSONA SCORES (avg across all scenarios)"
puts "=" * 60

scores = results.scores_by_candidate.sort_by { |_, s| -s[:avg_score] }
scores.each do |name, stats|
  bar   = "#" * (stats[:avg_score] * 2).round
  emoji = stats[:avg_score] >= 7 ? "✓" : "✗"
  puts "#{emoji} #{name.ljust(12)} #{stats[:avg_score].to_s.rjust(4)}/10  #{bar}"
end

puts "\n#{'=' * 60}"
puts "BY SCENARIO"
puts "=" * 60

results.scores_by_scenario.each do |scenario, candidate_scores|
  puts "\n#{scenario}:"
  ranked = candidate_scores.sort_by { |_, s| -s[:score] }
  ranked.each do |name, s|
    flag = s[:score] >= 7 ? "  " : "! "
    puts "  #{flag}#{name.ljust(12)} #{s[:score]}/10  #{s[:reasoning]&.slice(0, 80)}"
  end
end

low_scorers = scores.select { |_, s| s[:avg_score] < 7 }.map(&:first)
if low_scorers.any?
  puts "\nPersonas needing voice work: #{low_scorers.join(', ')}"
  puts "Inspect the HTML report for per-scenario reasoning, then adjust their YAMLs."
end

puts "\nDone. Total evaluations: #{results.evaluations.size}"
